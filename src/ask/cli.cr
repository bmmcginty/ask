# todo: make tools functions take Array(Tool)
# get_enabled_tools should return Array(Tool) for tools found in .tools that are available via the current model

require "option_parser"
require "yaml"
require "./message"
require "./config"
require "./model"
require "./models/*"
require "./tool"

module Ask
  class Cli
    @config : Config
    @model : Model

    def initialize
      @config = Config.new
      @model = get_model @config
    end

    # extract file references
    # <<filename
    def get_file_references(msg, base_filename = nil, force_cache = false)
      fns = msg.split("\n").select { |i| i.starts_with?("<<") }.map { |i| i[2..-1] }
      if force_cache
        cache = Dir.glob("#{base_filename}.b*.*")
        cache.select! { |i| i.match(/\.b([0-9]+)\./).not_nil![1].to_i? }
        if cache.size != fns.size
          raise Exception.new("original and cache attachments have different lengths\ncache: #{cache}\noriginal: #{fns}")
        end
        cache
      else
        fns
      end # if
    end   # def

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

    def get_enabled_tools
      t = Tools.new
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
      t = Tools.new
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
      t = Tools.new
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
      num = Dir.children(".").select do |i|
        i.match(/^[0-9]+[qacr]$/)
      end.sort_by do |i|
        i[0...-1].to_i
      end[-1][0...-1].to_i
      num += 1
      File.write(".restart",
        num.to_s)
    end

    # make a conversation.
    # If a question file exists, append it at the end of the conversation.
    # Post-processing will handle renaming it.
    # If the last file in the series is not a tool return, and no question file exists, throw an error.
    def construct_conversation(tools)
      files = Dir.children "."
      history = files.select { |i| i.match(/^[0-9]+[qacr]$/) }
      history.sort_by! { |i| i[0...-1].to_i }
      last = history.size > 0 ? history[-1] : ""
      if !files.includes?("question") && !last.ends_with?("r")
        raise Exception.new("no question file found")
      end
      if File.exists?("question")
        history << "question"
      end
      # if we have a .restart file,
      # we should disregard messages with ids before the .restart file
      if File.exists?(".restart")
        skip = File.read(".restart").strip.to_i
        history.reject! do |i|
          num = i[0...-1].to_i?
          num && num < skip
        end # reject
      end   # if .restart exists
      question_attachments = [] of String
      conversation = [] of Message
      num = 0
      history.each do |i|
        if t = i.match(/^([0-9]+)/)
          num = t[1].to_i
        end
        role = if i == "question"
                 "user"
               else
                 case i[-1]
                 when 'c'
                   "tool_call"
                 when 'r'
                   "tool_return"
                 when 'q'
                   "user"
                 when 'a'
                   "assistant"
                 else
                   raise Exception.new("unknown role #{i}")
                 end
               end # if \d+[qacr]
        msg = File.read(i)
        if i.match(/[0-9]+q|question/)
          # get the attachments listed in each file
          # if file is "question", use the attachments directly listed in the file
          # otherwise, use the local cached copy.
          attach = get_file_references msg, base_filename: i, force_cache: i != "question"
          if i == "question"
            question_attachments.concat attach
          end
          attach.each do |fn|
            m = if fn.match(/\.pdf$/i)
                  PDFMessage.new(role: role, filename: fn)
                elsif fn.match(/\.(png|jpg|tif|jpeg)$/i)
                  ImageMessage.new(role: role, filename: fn)
                else
                  TextMessage.new(role: role, text: File.read(fn))
                end # if
            conversation << m
          end # each attachment
          conversation << TextMessage.new(
            role: role,
            text: (
              msg.split("\n").reject { |i| i.match(/^<</) }.join("\n")
            ))
        elsif i.ends_with?("a")
          conversation << TextMessage.new(
            role: role,
            text: msg)
        elsif i.ends_with?("r")
          conversation << ToolReturnMessage.new(
            msg)
        elsif i.ends_with?("c")
          conversation << ToolCallMessage.new(
            msg)
        else
          raise Exception.new("invalid filename #{i}")
        end # if
      end   # each
      ({conversation, question_attachments})
    end # def

    # there should either be:
    # 1. a questionf ile
    # 1.1. Rename to conversation.size+1
    # 1.2. Cache any referenced attachments.
    # 2. or a tool return file
    # Throw an error if not 1 or 2.
    # Write each response to successive, numbered, typed files.
    # If the last response is a text response,
    # symlink the answer file.
    def postprocess(conversation, response, question_attachments, stop_reason)
      max_id = conversation.size
      if !File.exists?("question") && !conversation[-1].is_a?(ToolReturnMessage)
        raise Exception.new("conversation does not have a question file and did not send a tool return when asking")
      end
      if File.exists?("question")
        # if we have 01q 02a and question,
        # conversation.size==3
        # so max_id should be 2,
        # so max_id+1==3
        max_id -= 1
        question_filename = "#{(max_id + 1).to_s.rjust(2, '0')}q"
        File.rename "question", question_filename
        cache_attachments question_attachments, question_filename
        max_id += 1
      end
      answer_filename = nil
      response.each do |i|
        answer_filename = "#{(max_id + 1).to_s.rjust(2, '0')}#{(i.is_a?(ToolCallMessage) ? "c" : "a")}"
        File.open(answer_filename.not_nil!, "w") do |fh|
          i.write fh
        end
        max_id += 1
      end # each response
      if stop_reason.end_turn?
        if File.exists?("answer") && File.symlink?("answer")
          File.delete "answer"
        end # delete existing symlink
        if !File.exists?("answer")
          File.symlink answer_filename.not_nil!, "answer"
        end # symlink
      end   # non-tool response
      max_id
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
        conversation, question_attachments = construct_conversation(tools)
        response, stop_reason = @model.send conversation, tools
        last_id = postprocess(conversation, response, question_attachments, stop_reason)
        calls = response.select { |i| i.is_a?(ToolCallMessage) }
        if calls.size == 0
          break
        end
        calls.each do |i|
          tcm = i.as(ToolCallMessage)
          t = tools.select { |i| i.name == tcm.name }[0]
          t.on_validate do |v, schema|
            puts "#{tcm.name} #{v}"
            gets
            true
          end
          tool_rc, log_path = t.from_ai(tcm.parameters)
          tool_response = ToolReturnMessage.new(
            name: tcm.name,
            id: tcm.id,
            response: t.to_ai(log_path))
          File.open("#{(last_id + 1).to_s.rjust(2, '0')}r", "w") do |fh|
            tool_response.write fh
          end # fh
          last_id += 1
        end # each
      end   # while
    end     # def

  end # class

end # module
