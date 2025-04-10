require "yaml"

module Ask
  class Config
    @keys = Hash(String, String).new
    @default_model : String = ""
    @model_to_provider = Hash(String, String).new
    @prompt_caching = true
    @model_aliases = Hash(String, String).new
    getter default_model
    property prompt_caching

    def model_alias(name)
      @model_aliases[name]
    end

    def model_alias(name, default)
      @model_aliases.fetch(name, default)
    end

    def initialize
      load_config
      load_creds
    end

    def load_config
      all_aliases = Set(String).new
      dm = nil
      File.open(Path["~/.ask.yml"].expand(home: true), "r") do |io|
        cfg = YAML.parse io
        cfg["providers"].as_h.each do |provider, provider_cfg|
          provider_cfg["models"].as_h.each do |model, model_cfg|
            model_aliases = model_cfg["aliases"].as_a.map &.as_s
            dups = all_aliases & model_aliases.to_set
            if dups.size > 0
              raise Exception.new("#{model.as_s}/#{provider.as_s} has duplicate alias(es) #{dups.to_a.join(",")}")
            end # if dups
            all_aliases.concat model_aliases
            model_aliases.each do |alias_name|
              @model_aliases[alias_name] = model.as_s
            end # each alias
            @model_to_provider[model.as_s] = provider.as_s
          end # each model
        end   # each provider
        dm = cfg["default_model"].as_s
        dm = @model_aliases.fetch(dm, dm)
      end # io
      cfg_pl = @model_to_provider.values.uniq
      have_pl = Model.models.map &.provider
      invalid = cfg_pl.reject { |i| have_pl.includes?(i) }
      if invalid.size > 0
        raise Exception.new("invalid providers #{invalid.join(",")}")
      end # if
      @default_model = dm.not_nil!
    end

    def load_creds
      providers = @model_to_provider.values.uniq
      File.open(Path["~/.creds.yml"].expand(home: true), "r") do |io|
        creds = YAML.parse io
        creds = creds["ask"]
        have = creds.as_h.keys
        invalid = have.reject { |i| providers.includes?(i) }
        if invalid.size > 0
          raise Exception.new("invalid ask cred(s) found: #{invalid.join(",")} supported #{providers}")
        end # invalid
        have.each do |p|
          @keys[p.as_s] = creds[p]["api_key"].as_s
        end # each
      end   # io
    end     # def

    def provider(name)
      @model_to_provider[name.split("-")[0]]
    end

    def api_key(provider)
      @keys[provider]
    end
  end # class
end   # def
