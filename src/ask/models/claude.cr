require "nghttp/src/nghttp"

module Ask
  class ClaudeMessage
    @message : Message

    def content
      @message.content
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
              b.field "type", @message.type
              case @message.type
              when "text"
                b.field "text", @message.content
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
        rolling_char_sum = @messages[0..idx].sum { |i| i.content.size }
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

  class Claude
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
      msgs = ClaudeMessages.new(self, conversation)
      if @config.prompt_caching
        msgs.mark_cacheable
      end
      key = api_key
      h = HTTP::Headers.new
      h["Content-Type"] = "application/json"
      h["x-api-key"] = key
      h["anthropic-version"] = "2023-06-01"
      data = {
        "model"      => @model,
        "max_tokens" => 8192,
        "messages"   => msgs,
      }
      File.write("req.json", data.to_json)
      j = nil
      @s.post(
        "https://api.anthropic.com/v1/messages",
        headers: h,
        body: data.to_json) do |resp|
        j = resp.json
      end # request
      File.write("resp.json", j.to_json)
      j = j.not_nil!
      text = j["content"].as_a.map { |i| i["text"].as_s }
      text.join("\n\n")
    end # def
  end   # class
end     # module
