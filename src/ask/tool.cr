class Ask::Tools
  # holds tool definitions, schemas, and the actual binary (or a symlink to it)
  # ~/.ask/tools
  @definition_dir : Path
  # ~/.ask/logs
  @log_dir : Path
  @tools = [] of Tool

  getter tools

  def by_name_or_alias?(name)
    t = @tools.select { |i| i.name == name || i.alias == name }
    t[0]?
  end

  def by_name_or_alias(name)
    by_name_or_alias?(name).not_nil!
  end

  def initialize(definition_dir, log_dir)
    @definition_dir = Path[definition_dir].expand(home: true)
    @log_dir = Path[log_dir].expand(home: true)
  end

  def load_for_model(model)
    names = Dir.children(@definition_dir).select do |i|
      p = File.read(@definition_dir/i/"provider").strip
      p == model.class.provider || p == "*"
    end # each
    @tools = load(names)
  end # def

  def load(names)
    names.map { |name| Tool.new(@definition_dir/name, @log_dir) }
  end
end # class

alias Ask::ToolSchemaValidator = Proc(Ask::Tool, String, JSON::Any, Bool)

class Ask::Tool
  @alias = ""
  @dir : Path
  @base_log_dir : Path
  @on_validate : ToolSchemaValidator?
  @schema : JSON::Any
  @real_schema : JSON::Any
  @description : String

  getter schema, description

  def name
    @dir.basename
  end

  def alias
    @alias == "" ? nil : @alias
  end

  def initialize(@dir, @base_log_dir)
    if File.exists?(@dir/"alias")
      @alias = File.read(@dir/"alias").strip
    end
    @description = File.read(@dir/"description").strip
    @schema = jr "schema"
    @real_schema = jr? "validate_schema", @schema
    on_validate do |v, schema|
      false
    end
  end

  def on_validate(&block : ToolSchemaValidator)
    @on_validate = block
  end

  def on_validate=(validator : ToolSchemaValidator)
    @on_validate = validator
  end

  def jr(fn)
    JSON.parse(File.read(@dir/fn))
  end

  def jr?(fn, j2)
    if File.exists?(@dir/fn)
      JSON.parse(File.read(@dir/fn))
    else
      j2
    end
  end

  def from_ai(j : JSON::Any)
    tool_name = @dir.basename
    ts = Time.local.to_s("%Y-%m-%d/%H:%M:%S")
    log_path = @base_log_dir/"#{tool_name}/#{ts}"
    validate_against_json_schema j.to_json, @real_schema, "ai-to-tool schema validation failed"
    ret = nil
    Dir.mkdir_p log_path
    File.open(log_path/"stdin", "w+") do |input_io|
      File.open(log_path/"stdout", "w") do |output_io|
        File.open(log_path/"stderr", "w") do |error_io|
          input_io << j.to_json
          input_io.seek 0
          sp = Process.new(
            command: (@dir/"exe").to_s,
            input: input_io,
            error: error_io,
            output: output_io)
          ret = sp.not_nil!.wait.exit_code
        end # do
      end   # do
    end     # do
    ({ret.not_nil!, log_path})
  end

  def to_ai(log_path)
    t = File.read(log_path/"stdout")
    JSON.parse t
  end

  def validate_against_json_schema(untrusted, schema, message)
    t = @on_validate
    if t
      if !t.call(self, untrusted, schema)
        raise Exception.new("#{message}\n#{schema}\n#{untrusted}")
      end # if
    end   # if t
  end     # def

end # class
