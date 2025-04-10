require "nghttp/src/nghttp"

module Ask
  class ClaudeTools
  end

  class ClaudeMessage
    @message : Message

    def quick_size
      @message.quick_size
    end

    def initialize(@message)
    end

    def to_json(b : JSON::Builder, cache = false)
      b.object do
        b.field "role", @message.role
        b.field "content" do
          b.array do
            b.object do
              if cache
                b.field "cache_control" do
                  b.object do
                    b.field "type", "ephemeral"
                  end # object
                end   # cache_control field
              end     # if cache
              case @message
              when ToolCallMessage
                m = @message.as(ToolCallMessage)
                b.field "type", "tool_use"
                b.field "id", m.id
                b.field "name", m.name
                b.field "input", m.parameters
              when ToolReturnMessage
                m = @message.as(ToolReturnMessage)
                b.field "type", "tool_result"
                b.field "tool_use_id", m.id
                b.field "content", m.response.to_json
              when TextMessage
                m = @message.as(TextMessage)
                b.field "type", "text"
                b.field "text", m.text
              when PDFMessage, ImageMessage
                m = @message.as(MediaMessage)
                b.field "type", (@message.is_a?(PDFMessage) ? "document" : "image")
                b.field "source" do
                  b.object do
                    b.field "type", "base64"
                    b.field "media_type", m.media_type
                    b.field "data", m.base64
                  end # source
                end   # source field
              else
                raise Exception.new("unknown type #{@message.type}")
              end
            end # object
          end   # array
        end     # content field
      end       # object
    end         # def

  end # class

  class ClaudeMessages
    @messages : Array(ClaudeMessage)
    @cacheable = [] of Int32
    @ai : Claude

    def initialize(@ai, conversation)
      @messages = conversation.map { |i| ClaudeMessage.new(i) }
    end

    def to_json(b : JSON::Builder)
      idx = 0
      b.array do
        @messages.each do |i|
          idx += 1
          i.to_json(b, cache: @cacheable.includes?(idx))
        end # each message
      end   # array
    end     # def

    def mark_cacheable
      c = [] of Int32
      min_length = if @ai.model.match /haiku/i
                     2048
                   else
                     1024
                   end
      idx = -1
      @messages.each do |i|
        idx += 1
        # 1 token ~ 4 chars
        rolling_char_sum = @messages[0..idx].sum { |i| i.quick_size }
        if (rolling_char_sum / 4) >= min_length
          c << idx
        end # if
      end   # each message
      @cacheable = find_greatest_consecutive_ids(c)
    end

    def find_greatest_consecutive_ids(l)
      ret = [] of Int32
      while l.size > 0
        num = l.shift
        # if we haven't seen any numbers yet, this number is the start of a new group (the first group in fact)
        if ret.size == 0
          ret << num
          next
        end
        # if this number is in the same consecutive group, replace the previous number with this one
        if num == ret[-1] + 1
          ret[-1] = num
          next
        end
        # otherwise, we're in a new group, so append the current id and continue
        ret << num
      end # while
      ret
    end # def

  end

  class Claude < Model
    def self.match
      /claude.*/i
    end

    def self.provider
      "anthropic"
    end

    def send(conversation, tools)
      msgs = ClaudeMessages.new(self, conversation)
      if @config.prompt_caching
        msgs.mark_cacheable
      end
      key = api_key
      h = HTTP::Headers.new
      h["Content-Type"] = "application/json"
      h["x-api-key"] = key
      h["anthropic-version"] = "2023-06-01"
      data = JSON.build do |builder|
        builder.object do
          builder.field "model", @model
          builder.field "max_tokens", 8192
          builder.field "messages", msgs
          if tools.size > 0
            builder.field "tools" do
              builder.array do
                tools.each do |i|
                  builder.object do
                    builder.field "name", i.name
                    builder.field "description", i.description
                    builder.field "input_schema", i.schema
                  end # tool object
                end   # each tool
              end     # array
            end       # tools
          end         # if
        end           # object
      end             # builder
      do_on_request data
      j = nil
      @s.post(
        "https://api.anthropic.com/v1/messages",
        headers: h,
        body: data) do |resp|
        j = resp.json
      end # request
      do_on_response j.to_json
      j = j.not_nil!
      stop_reason = case j["stop_reason"].as_s
                    when "end_turn"
                      StopReason::EndTurn
                    when "tool_use"
                      StopReason::ToolCall
                    else
                      raise Exception.new("invalid stop reason")
                    end
      ret = [] of Message
      j["content"].as_a.each do |i|
        t = i["type"].as_s
        case t
        when "tool_use"
          ret << ToolCallMessage.new(
            id: i["id"].as_s,
            name: i["name"].as_s,
            parameters: i["input"])
        when "text"
          ret << TextMessage.new role: "assistant", text: i["text"].as_s
        else
          raise Exception.new("invalid message type #{i.to_json}")
        end # case
      end   # each
      ({ret, stop_reason})
    end # def
  end   # class
end     # module
