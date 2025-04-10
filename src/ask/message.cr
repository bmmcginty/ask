module Ask
  enum StopReason
    EndTurn
    ToolCall
  end

  abstract class Message
    abstract def role

    def write(io : IO)
      raise Exception.new("can not write #{self.class.name} to files as of this release")
    end
  end # class

  class TextMessage < Message
    @type = "text"
    @role : String
    @text : String
    getter type, role, text

    def quick_size
      @text.size
    end

    def initialize(@role, @text)
    end

    def write(io : IO)
      io << @text
    end
  end # class

  abstract class MediaMessage < Message
    @role : String
    @filename : String

    abstract def media_type

    def quick_size
      base64.size
    end

    def initialize(@role, @filename)
    end

    def filename
      @filename
    end

    def initialize(@role, @filename)
    end

    def base64
      Base64.strict_encode(File.read(@filename))
    end
  end

  class PDFMessage < MediaMessage
    getter role

    def type
      "document"
    end

    def media_type
      "application/pdf"
    end
  end # class

  class ImageMessage < MediaMessage
    getter role

    def type
      "image"
    end

    def media_type
      ext = @filename.split(".")[-1].downcase
      case ext
      when "jpg"
        "image/jpeg"
      when "gif", "png", "webp"
        "image/#{ext}"
      else
        raise Exception.new("invalid format #{ext} for #{@filename}")
      end
    end
  end # class

  abstract class ToolMessage < Message
    abstract def role
    abstract def type

    def content
      raise Exception.new("no plain content field for tool messages")
    end
  end

  class ToolCallMessage < ToolMessage
    @role = "assistant"
    @type = "tool_call"
    @id : String
    @name : String
    @parameters : JSON::Any
    getter role, type, name, parameters, id

    def quick_size
      name.size + parameters.to_json.size + id.to_s.size
    end

    def self.new(data : String)
      j = JSON.parse data
      new(
        name: j["name"].as_s,
        parameters: j["parameters"],
        id: j["id"].as_s)
    end

    def initialize(@name, @parameters, @id = "")
    end # def

    def write(io : IO)
      jb = JSON::Builder.new io
      jb.document do
        jb.object do
          jb.field "name", name
          jb.field "parameters", parameters
          jb.field "id", id
        end # object
      end   # document
    end     # def

  end # class

  class ToolReturnMessage < ToolMessage
    @role = "user"
    @type = "tool_return"
    @id : String
    @name : String
    @response : JSON::Any
    getter type, role, name, response, id

    def quick_size
      name.size + response.to_json.size + id.to_s.size
    end

    def self.new(data : String)
      j = JSON.parse data
      new(
        name: j["name"].as_s,
        response: j["response"],
        id: j["id"].as_s)
    end

    def initialize(@name, @response, @id = "")
    end

    def write(io : IO)
      jb = JSON::Builder.new io
      jb.document do
        jb.object do
          jb.field "name", name
          jb.field "response", response
          jb.field "id", id
        end # object
      end   # document
    end     # def

  end # class

end # module
