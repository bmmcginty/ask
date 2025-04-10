class Ask::Model
  @@models = [] of Model.class

  def self.models
    @@models
  end

  macro inherited
    Model.models << self
  end

  @config : Config
  @model : String
  @s : NGHTTP::Session
  getter model
  @on_request : (String ->)? = nil
  @on_response : (String ->)? = nil

  def on_request(&block : (String ->))
    @on_request = block
  end

  def on_response(&block : (String ->))
    @on_response = block
  end

  def do_on_request(d)
    if t = @on_request
      t.call d
    end
  end

  def do_on_response(d)
    if t = @on_response
      t.call d
    end
  end

  def initialize(@config, @model)
    @s = NGHTTP::Session.new
    @s.config.read_timeout = 120.seconds
  end

  def api_key
    @config.api_key self.class.provider
  end # def

  def self.provider
    raise Exception.new("can not call provider on base model class")
  end

  def self.match
    raise Exception.new("can not call match on base model class")
  end

  def send(conversation, tools)
    raise Exception.new("can not call send on base model class")
  end
end # class
