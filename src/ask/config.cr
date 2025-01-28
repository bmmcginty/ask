require "yaml"

module Ask
  class Config
    @keys = Hash(String, String).new
    @default_model : String
    @model_to_provider = Hash(String, String).new
    @prompt_caching = true
    getter default_model
    property prompt_caching

    def initialize
      providers = [] of String
      dm = nil
      File.open(Path["~/.ask.yml"].expand(home: true), "r") do |io|
        cfg = YAML.parse io
        cfg["providers"].as_h.each do |k, v|
          if v["provider"]?
            @model_to_provider[k.as_s] = v["provider"].as_s
          end
          providers << k.as_s
        end
        dm = cfg["default_model"].as_s
      end # io
      @default_model = dm.not_nil!
      File.open(Path["~/.creds.yml"].expand(home: true), "r") do |io|
        creds = YAML.parse io
        have = creds.as_h.keys.select { |i| providers.includes?(i) }
        have.each do |p|
          @keys[p.as_s] = creds[p]["api_key"].as_s
        end # each
      end   # io
    end     # def

    def provider(name)
      @model_to_provider[name.split("-")[0]]
    end

    def api_key(name)
      @keys[name]
    end
  end # class
end   # def
