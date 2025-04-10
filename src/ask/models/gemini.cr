require "nghttp/src/nghttp"

module Ask
  class GeminiTools
    @tools : Array(Tool)

    def initialize(@tools)
    end

    def to_json(b : JSON::Builder)
      b.array do
        b.object do
          b.field "functionDeclarations" do
            b.array do
              @tools.each do |t|
                b.object do
                  b.field "name", t.name
                  b.field "description", t.description
                  b.field "parameters", t.schema
                end # object
              end   # each t
            end     # array
          end       # field
        end         # object
      end           # array
    end             # def
  end               # class

  class GeminiMessage
    @message : Message

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
              case @message
              when ToolCallMessage
                m = @message.as(ToolCallMessage)
                b.field "functionCall" do
                  b.object do
                    b.field "name", m.name
                    b.field "args", m.parameters
                  end # object
                end   # function call
              when ToolReturnMessage
                m = @message.as(ToolReturnMessage)
                b.field "functionResponse" do
                  b.object do
                    b.field "name", m.name
                    b.field "response" do
                      b.object do
                        b.field "name", m.name
                        b.field "response", m.response
                      end # response object
                    end   # response field
                  end     # object
                end       # function response
              when TextMessage
                m = @message.as(TextMessage)
                b.field "text", m.text
              when ImageMessage, PDFMessage
                m = @message.as(MediaMessage)
                b.field "inline_data" do
                  b.object do
                    b.field "mime_type", m.media_type
                    b.field "data", m.base64
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

  class Gemini < Model
    def self.match
      /gemini.*/i
    end

    def self.provider
      "google"
    end

    def send(conversation, tools)
      msgs = GeminiMessages.new(self, conversation)
      # prompt caching unavailable for <32768 tokens so will wait on this
      # @config.prompt_caching
      key = api_key
      h = HTTP::Headers.new
      h["Content-Type"] = "application/json"
      data = JSON.build do |b|
        b.object do
          if tools.size > 0
            b.field "tools", GeminiTools.new(tools)
          end # if
          b.field "contents", msgs
        end # object
      end   # jb
      do_on_request data
      j = nil
      @s.post(
        "https://generativelanguage.googleapis.com/v1beta/models/#{@model}:generateContent",
        params: {"key" => key},
        headers: h,
        body: data) do |resp|
        j = resp.json
      end # request
      do_on_response j.to_json
      j = j.not_nil!
      fc = j["candidates"][0]["content"]["parts"][0]["functionCall"]?
      sr = j["candidates"][0]["finishReason"].as_s
      stop_reason = if fc
                      StopReason::ToolCall
                    elsif sr == "STOP"
                      StopReason::EndTurn
                    else
                      raise Exception.new("unknown finish reason")
                    end # case
      ret = [] of Message
      j["candidates"][0]["content"]["parts"].as_a.each do |i|
        if f = i["functionCall"]?
          f = f.as_h
          ret << ToolCallMessage.new(
            name: f["name"].as_s,
            parameters: f["args"])
        elsif i["text"]?
          ret << TextMessage.new(
            role: "assistant",
            text: i["text"].as_s)
        end # if
      end   # each
      ({ret, stop_reason})
    end # def
  end   # class
end     # module
