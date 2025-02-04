require "option_parser"
require "./message"
require "./config"
require "./models/*"

module Ask
  class Cli
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

    def get_model(config, model)
      short = model.split("-")[0].downcase
      cls = case short
            when "claude"
              Claude
            else
              raise Exception.new("unknown model for #{short}")
            end
      cls.new(config: config, model: model)
    end

    def run
      restart = false
      parser = OptionParser.new do |p|
        p.on("restart", "start chat history refresh from this pont") do
          restart = true
        end # restart conversation
      end   # build parser
      parser.parse
      if restart
        restart_conversation
      else
        ask_question
      end # else
    end   # def

    def restart_conversation
      num = Dir.children(".").select do |i|
        i.match(/^[0-9]+[qa]$/)
      end.sort_by do |i|
        i[0...-1].to_i
      end[-1][0...-1].to_i
      num += 1
      File.write(".restart",
        num.to_s)
    end

    def ask_question
      puts "running"
      c = Config.new
      files = Dir.children "."
      if files.includes?(".nocache")
        c.prompt_caching = false
      end
      if !files.includes?("question")
        raise Exception.new("no question file found")
      end
      history = files.select { |i| i.match(/^[0-9]+[qa]$/) }
      history.sort_by! { |i| i[0...-1].to_i }
      question_filename = (history.size + 1).to_s.rjust(2, '0') + "q"
      answer_filename = (history.size + 2).to_s.rjust(2, '0') + "a"
      history << "question"
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
      history.each do |i|
        num = nil
        if t = i.match(/^([0-9]+)/)
          num = t[1].to_i
        end
        role = if i == "question"
                 "user"
               else
                 case i[-1]
                 when 'q'
                   "user"
                 when 'a'
                   "assistant"
                 else
                   raise Exception.new("unknown role #{i}")
                 end
               end # if \d+[qa]
        msg = File.read(i)
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
              else
                ImageMessage.new(role: role, filename: fn)
              end
          conversation << m
        end # if attachments
        conversation << TextMessage.new(
          role: role,
          text: (
            msg.split("\n").reject { |i| i.match(/^<</) }.join("\n")
          ))
      end # map
      model = if File.exists?(".model")
                File.read(".model")
              else
                c.default_model
              end.strip # if
      m = get_model(config: c, model: model)
      response = m.send conversation
      File.write answer_filename, response
      File.rename "question", question_filename
      cache_attachments question_attachments, question_filename
      if File.exists?("answer") && File.symlink?("answer")
        File.delete "answer"
      end
      if !File.exists?("answer")
        File.symlink answer_filename, "answer"
      end
    end # def

  end # class

end # module
