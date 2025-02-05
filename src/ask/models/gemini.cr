require "nghttp/src/nghttp"

module Ask
  class GeminiMessage
    @message : Message

    def content
      @message.content
    end

    def initialize(@message)
    end

    def to_json(b : JSON::Builder)
      b.object do
        b.field "role", case @message.role
        when "assistant"
          "model"
        else
          "user"
        end # role
        b.field "parts" do
          b.array do
            b.object do
              case @message.type
              when "text"
                b.field "text", @message.content
              when "image", "document"
                b.field "inline_data" do
                  b.object do
                    b.field "mime_type", @message.media_type
                    b.field "data", @message.content
                  end # inline_data
                end   # source object
              else
                raise Exception.new("unknown type #{@message.type}")
              end
            end # object
          end   # array
        end     # content field
      end       # object
    end         # def

  end # class

  class GeminiMessages
    @messages : Array(GeminiMessage)
    @ai : Gemini

    def initialize(@ai, conversation)
      @messages = conversation.map { |i| GeminiMessage.new(i) }
    end

    def to_json(b : JSON::Builder)
      idx = 0
      b.array do
        @messages.each do |i|
          idx += 1
          i.to_json(b)
        end # each message
      end   # array
    end     # def

  end # class

  class Gemini
    @config : Config
    @model : String
    @s : NGHTTP::Session
    getter model

    def initialize(@config, @model)
      @s = NGHTTP::Session.new
      @s.config.read_timeout = 120.seconds
    end

    def api_key
      name = @model.split(/[-_]/)[0].downcase
      @config.api_key(name)
    end

    def send(conversation)
      msgs = GeminiMessages.new(self, conversation)
      # prompt caching unavailable for <32768 tokens so will wait on this
      # @config.prompt_caching
      key = api_key
      h = HTTP::Headers.new
      h["Content-Type"] = "application/json"
      data = {
        "contents" => msgs,
      }
      File.write("req.json", data.to_json)
      j = nil
      @s.post(
        "https://generativelanguage.googleapis.com/v1beta/models/#{@model}:generateContent",
        params: {"key" => key},
        headers: h,
        body: data.to_json) do |resp|
        j = resp.json
      end # request
      File.write("resp.json", j.to_json)
      j = j.not_nil!
      text = j["candidates"][0]["content"]["parts"].as_a.map { |i| i["text"].as_s }
      text.join("\n\n")
    end # def
  end   # class
end     # module
