module Ask
  abstract class Message
    abstract def type
    abstract def content
    abstract def role

    def media_type
      raise Exception.new("media_type not valid for text message")
    end # def
  end   # class

  class TextMessage < Message
    @type = "text"
    @role : String
    @text : String
    getter type, role

    def initialize(@role, @text)
    end

    def content
      @text
    end
  end # class

  class PDFMessage < Message
    @type = "document"
    @role : String
    @filename : String
    getter role, type

    def initialize(@role, @filename)
    end

    def media_type
      "application/pdf"
    end

    def content
      Base64.strict_encode(File.read(@filename))
    end
  end # class

  class ImageMessage < Message
    @type = "image"
    @role : String
    @filename : String
    getter role, type, filename

    def initialize(@role, @filename)
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

    def content
      Base64.strict_encode(File.read(@filename))
    end
  end # class

end # module
