module Ask
  abstract class Message
    abstract def type
    abstract def content
    abstract def role
  end # class

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

end # module
