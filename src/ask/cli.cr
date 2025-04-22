require "option_parser"
require "yaml"
require "./message"
require "./config"
require "./model"
require "./models/*"
require "./tool"

module Ask
  # An entry can be:
  # 1. question file
  # 2. \d+[qacr] file
  # where \d+ is a number > 0
  # and [qacr] is a one letter code that gives the role and type of the files contents
  # 3. a Message object that represents a tool/question/answer that has not yet been written to disk
  class ConversationEntry
    @@regex = /^(\d+)([qacr])$/
    @filename : String? = nil
    @written = false
    @message : Message? = nil

    getter! message
    getter! filename
    property written

    def message_suffix
      if message.is_a?(ToolReturnMessage)
        "r"
      elsif message.is_a?(ToolCallMessage)
        "c"
      elsif message.role == "user"
        "q"
      elsif message.role == "assistant"
        "a"
      else
        raise Exception.new("unknown suffix for message #{message}")
      end
    end

    def num?
      t = nil
      if @filename
        t = filename.match(@@regex)
      end
      t && t[1].to_i > 0 ? t[1].to_i : nil
    end

    def num
      num?.not_nil!
    end

    def valid?
      (@filename && @filename == "question") || (num? && suffix?)
    end

    def suffix?
      t = nil
      if @filename
        t = filename.match(@@regex)
      end
      t ? t[2] : nil
    end

    def suffix
      suffix?.not_nil!
    end

    def initialize(@filename : String)
      @written = true
    end

    def initialize(@message : Message)
      @written = false
    end

    # if question has
    # <<a.pdf
    # question will generate a PDFMessage (a.pdf)
    # and a TextMessage (question)
    # Only new responses are reimported back into the on-disk conversation,
    # not the original exported conversation,
    # because the ai has no way to know that we referenced a.pdf from our question.
    # IOW ConversationList.add_messages must not be supplied with the messages coming from ConversationEntry.to_message
    def to_message
      ret = [] of Message
      role = if filename == "question" || suffix == "q" || suffix == "c"
               "user"
             elsif suffix == "a" || suffix == "r"
               "assistant"
             else
               raise Exception.new("unknown suffix for #{filename}")
             end
      ret << if filename == "question" || suffix == "q"
        refs, msg = get_file_references
        refs.each do |ref|
          ret << reference_to_message ref
        end # each
        TextMessage.new(
          role: role,
          text: msg)
      elsif suffix == "a"
        msg = File.read(filename)
        TextMessage.new(
          role: role,
          text: msg)
      elsif suffix == "c"
        ToolCallMessage.new(File.read(filename))
      elsif suffix == "r"
        ToolReturnMessage.new(File.read(filename))
      else
        raise Exception.new("invalid filename #{filename}")
      end # if
      ret
    end # def

    def reference_to_message(ref)
      fn = ref.to_s
      if fn.match(/\.pdf$/i)
        PDFMessage.new(role: "user", filename: fn)
      elsif fn.match(/\.(gif|jpg|png|webp)$/i)
        ImageMessage.new(role: "user", filename: fn)
      else
        # do not process nested file references
        TextMessage.new(
          role: "user",
          text: File.read(fn))
      end # if
    end   # def

    def get_file_references
      msg = [] of String
      attachments = [] of Path
      File.read(filename).split("\n").each do |i|
        if i.starts_with?("<<")
          attachments << Path[i[2..-1]].expand(home: true)
        else
          msg << i
        end
      end
      ({attachments, msg.join("\n")})
    end
  end

  # holds a list of all valid conversation entries
  # calling entries_from_disk should
  # 1. return all on-disk entries with
  # a. filename of "question"
  # b. or with a valid number >= @restart
  # calling write should
  # 1. determine the lowest id we can write to (lowest_id)
  # This is the greater of
  # a. @restart
  # b. one higher than the greatest valid file number
  # c. 1 if no files with valid file numbers exist
  # 2. if question exists
  # 2.1. rename question to ${lowest_id}q (qfn)
  # 2.2. replace question with Entry.new(qfn)
  # 3. for each entry where .written is false:
  # 3.1. increase lowest_id by 1
  # 3.2. write entry.message to ${lowest_id}#{entry.message_suffix} (new_fn)
  # 3.3. replace entry with Entry.new(new_fn)
  # 4. symlink answer to the last assistant file received
  class ConversationEntries
    @list = [] of ConversationEntry
    @restart = -1

    def to_messages(tools)
      ret = [] of Message
      entries_from_disk.each do |e|
        ret.concat e.to_message
      end
      ret
    end

    def entries_from_disk
      ret = @list.select { |i| i.num? }.sort_by { |i| i.num }
      if @restart > -1
        ret.reject! { |i| i.num < @restart }
      end
      if q = self["question"]?
        ret << q
      end
      ret
    end

    def lowest_writeable_id
      greatest = @list.select { |i| i.num? }.map { |i| i.num }.sort
      # if there are no files, the next writeable number will be 1,
      greatest = if greatest.size == 0
                   0
                 else
                   greatest[-1]
                 end
      # if there are no files, greatest+1 will turn 0 into 1
      [@restart, greatest + 1].max
    end

    def write
      lowest_id = lowest_writeable_id
      to_cache = nil
      q_entry = nil
      if q = self["question"]?
        pos = @list.index(q).not_nil!
        qfn = "#{lowest_id.to_s.rjust(2, '0')}q"
        File.rename "question", qfn
        lowest_id += 1
        q_entry = ConversationEntry.new qfn
        to_cache = q_entry.get_file_references[0]
        @list[pos] = q_entry.not_nil!
      end
      written_answers = [] of Int32
      @list.size.times do |idx|
        i = @list[idx]
        next if i.written
        new_fn = "#{lowest_id.to_s.rjust(2, '0')}#{i.message_suffix}"
        if i.message_suffix == "a"
          written_answers << idx
        end
        File.open(new_fn, "w") do |fh|
          i.message.write fh
        end # write
        lowest_id += 1
        @list[idx] = ConversationEntry.new filename: new_fn
      end # each
      if to_cache
        link_file_references q_entry, to_cache
      end # if
      if written_answers.size > 0
        af = @list[written_answers[-1]]
        link_answer af
      end
    end # def

    def link_answer(answer_entry)
      if File.exists?("answer") && File.symlink?("answer")
        File.delete "answer"
      end # delete existing symlink
      if !File.exists?("answer")
        File.symlink answer_entry.filename, "answer"
      end # symlink
    end   # def

    def link_file_references(q, files)
      # do nothing for now
      # make q_fn+".b#{idx}" for idx in attachments
    end

    def []?(name)
      @list.select { |i| i.filename? == name }[0]?
    end

    def [](name)
      self.[]?(name).not_nil!
    end

    def add_messages(messages)
      messages.each do |m|
        @list << ConversationEntry.new message: m
      end
    end

    def check_valid
      # must have a question file or a function call file
      last = entries_from_disk[-1]
      last == self["question"]? || last[-1].suffix == "c"
    end

    def initialize
      Dir.children(".").each do |i|
        if i == ".restart"
          @restart = File.read(".restart").strip.to_i
          next
        end
        entry = ConversationEntry.new filename: i
        next if !entry.valid?
        @list << entry
      end # each
    end   # def

  end # class

  class Cli
    @tools_dir : String
    @tools_log_dir : String
    @config_filename : String
    @creds_filename : String
    @config : Config
    @model : Model

    def initialize(
      @tools_dir = "~/.ask/tools",
      @tools_log_dir = "~/.ask/logs",
      @config_filename = "~/.ask.yml",
      @creds_filename = "~/.creds.yml",
    )
      @config = Config.new config_filename: @config_filename, creds_filename: @creds_filename
      @model = get_model @config
    end

    # copy file references from source_file into base_filename.bNNN
    # where NNN is a zero padded number
    # cache_attachments("<</tmp/a.jpg", "q01") # q0a.b01.jpg
    def cache_attachments(attach, base_filename)
      ret = [] of String
      attach.each_with_index do |fn, idx|
        anum = (idx + 1).to_s.rjust(attach.size.to_s.size, '0')
        ext = fn.split(".")[-1].downcase
        nn = "#{base_filename}.b#{anum}.#{ext}"
        File.copy fn, nn
        ret << nn
      end # each
      ret
    end # def

    def get_model(config)
      model_name = if File.exists?(".model")
                     File.read(".model")
                   else
                     config.default_model
                   end.strip # if
      model_name = config.model_alias(model_name, model_name)
      matches = Model.models.select do |i|
        i.match.match(model_name)
      end
      if matches.size != 1
        raise Exception.new("#{matches} models for #{model_name}")
      end
      matches[0].new(config: config, model: model_name)
    end

    def run
      restart = false
      enable = [] of String
      do_tools = :nothing
      parser = OptionParser.new do |p|
        p.unknown_args do |args|
          next if args.size == 0
          puts p
          exit 1
        end
        p.on("tool", "manage tool use") do
          do_tools = :list
          p.unknown_args do |args|
            next if args.size == 0
            puts args, p
            exit 1
          end # invalid
          p.on("enable", "enable tool") do
            do_tools = :enable
            p.unknown_args do |args|
              enable.concat args
            end # name
          end   # enable
        end     # tool
        p.on("restart", "start chat history refresh from this point") do
          restart = true
        end # restart conversation
      end   # build parser
      parser.parse
      if restart
        restart_conversation
      elsif do_tools == :enable
        enable_tools enable
      elsif do_tools == :list
        list_tools
      else
        ask_question
      end # else
    end   # def

    def new_tools
      Tools.new definition_dir: @tools_dir, log_dir: @tools_log_dir
    end

    def get_enabled_tools
      t = new_tools
      t.load_for_model(@model)
      if !File.exists?(".tools")
        [] of Tool
      else
        existing = parse_dot_tools.keys
        existing = existing.map { |i| t.by_name_or_alias(i) }
        existing
      end
    end

    # Given a list of tool names,
    # add all or none of the tools to the .tools yaml file.
    def enable_tools(enable)
      t = new_tools
      t.load_for_model(@model)
      existing = if File.exists?(".tools")
                   parse_dot_tools.keys
                 else
                   [] of String
                 end
      existing = existing.map { |i| t.by_name_or_alias(i) }
      add = enable.select { |i| t.by_name_or_alias?(i) }.map { |i| t.by_name_or_alias(i) }
      errors = [] of Tuple(String, String)
      if enable.size == 0
        errors << ({"none", "no tools specified"})
      end
      add.each do |i|
        if existing.includes?(i)
          errors << ({i.name, "already enabled"})
        end
      end
      enable.each do |i|
        if !t.by_name_or_alias?(i)
          errors << ({i, "not found"})
        end # if
      end   # each
      if errors.size > 0
        puts "errors:"
        errors.each do |i, j|
          puts "#{i}: #{j}"
        end # each
        exit 1
      end # if
      dt = if File.exists?(".tools")
             parse_dot_tools
           else
             Hash(String, Hash(String, String)).new
           end
      enable.each do |i|
        dt[i] = Hash(String, String).new
      end
      write_dot_tools dt
    end # def

    def parse_dot_tools
      y = YAML.parse(File.read(".tools"))
      h = Hash(String, Hash(String, String)).new
      y.as_h.each do |name, cfg|
        h[name.as_s] = Hash(String, String).new
        cfg.as_h.each do |cfg_key, cfg_val|
          h[name.as_s][cfg_key.as_s] = cfg_val.as_s
        end # each cfg key
      end   # each tool
      h
    end

    def write_dot_tools(data)
      File.write(".tools.tmp", data.to_yaml)
      File.rename ".tools.tmp", ".tools"
    end

    def list_tools
      t = new_tools
      t.load_for_model(@model)
      dt = if File.exists?(".tools")
             parse_dot_tools
           else
             [] of String
           end
      t.tools.each do |t|
        star = " "
        if dt.includes?(t.name) || dt.includes?(t.alias)
          star = "*"
        end
        puts "#{star}#{t.name}"
      end
    end

    def restart_conversation
      l = ConversationEntries.new
      num = l.lowest_writeable_id
      File.write(".restart",
        num.to_s)
    end

    def process_response(response, tools, stop_reason, &block : ToolSchemaValidator)
      calls = response.select { |i| i.is_a?(ToolCallMessage) }
      if calls.size == 0
        return false
      end
      ret = false
      calls.each do |i|
        tcm = i.as(ToolCallMessage)
        t = tools.select { |i| i.name == tcm.name }[0]
        t.on_validate = block
        tool_rc, log_path = t.from_ai(tcm.parameters)
        tool_response = ToolReturnMessage.new(
          name: tcm.name,
          id: tcm.id,
          response: t.to_ai(log_path))
        response << tool_response
        ret = true
      end # each
      ret
    end # def

    def ask_question
      puts "running"
      @model.on_request do |data|
        File.write "req.#{Time.local.to_unix_ms}.json", data
      end
      @model.on_response do |data|
        File.write "resp.#{Time.local.to_unix_ms}.json", data
      end
      while 1
        tools = get_enabled_tools
        if File.exists?(".nocache")
          @config.prompt_caching = false
        end
        cl = ConversationEntries.new
        messages = cl.to_messages(tools)
        response, stop_reason = @model.send messages, tools
        continue_conversation = process_response response: response, tools: tools, stop_reason: stop_reason do |tool, args, schema|
          puts "#{tool.name} #{args}"
          gets
          true
        end
        cl.add_messages response
        cl.write
        break if !continue_conversation
      end # while
    end   # def

  end # class

end # module
