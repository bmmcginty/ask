require "./message"
require "./config"
require "./models/*"

module Ask
  def self.get_model(config, model)
    short = model.split("-")[0].downcase
    cls = case short
          when "claude"
            Claude
          else
            raise Exception.new("unknown model for #{short}")
          end
    cls.new(config: config, model: model)
  end

  def self.cli
    puts "running"
    c = Config.new
    files = Dir.children "."
    if !files.includes?("question")
      raise Exception.new("no question file found")
    end
    history = files.select { |i| i.match(/^[0-9]+[qa]$/) }
    history.sort_by! { |i| i[0...-1].to_i }
    question_filename = (history.size + 1).to_s.rjust(2, '0') + "q"
    answer_filename = (history.size + 2).to_s.rjust(2, '0') + "a"
    history << "question"
    conversation = history.map do |i|
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
      TextMessage.new(
        role: role,
        text: File.read(i))
    end # map
    model = if File.exists?(".model")
              File.read(".model")
            else
              c.default_model
            end.strip # if
    m = get_model(config: c, model: model)
    response = m.send conversation
    File.rename "question", question_filename
    File.write answer_filename, response
    if File.exists?("answer") && File.symlink?("answer")
      File.delete "answer"
    end
    if !File.exists?("answer")
      File.symlink answer_filename, "answer"
    end
  end # def

end # module
