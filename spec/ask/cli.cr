require "file_utils"
require "../../src/ask/cli"

def print_dir
  Dir.children(".").sort.each do |i|
    puts "#{i}:\n#{File.read(i)}\n$$"
  end
end

def tempdir(&)
  old = Dir.current
  dn = `mktemp -d`.strip
  raise Exception.new("empty dir") if dn.size == 0
  begin
    Dir.cd dn
    yield dn
  ensure
    Dir.cd old
    FileUtils.rm_rf dn
  end
end

describe "cli" do
  it "should create empty dir" do
    l = nil
    tempdir do |d|
      l = d
      Dir.exists?(d).should eq true
    end # do
    Dir.exists?(l.not_nil!).should eq false
  end # it

  it "should return 0 entries" do
    tempdir do
      cl = Ask::ConversationEntries.new
      cl.entries_from_disk.size.should eq 0
    end
  end

  it "should return 1 entry" do
    tempdir do
      File.write "01q", "2+2"
      cl = Ask::ConversationEntries.new
      l = cl.entries_from_disk
      l.size.should eq 1
    end
  end

  it "should return 2 entries" do
    tempdir do
      File.write "01q", "2+2"
      File.write "question", "4+4"
      cl = Ask::ConversationEntries.new
      l = cl.entries_from_disk
      l.size.should eq 2
    end
  end

  it "should convert messages" do
    tempdir do
      File.write "01q", "2+2"
      File.write "question", "4+4"
      cl = Ask::ConversationEntries.new
      l = cl.entries_from_disk
      l.size.should eq 2
      msgs = cl.to_messages(Array(Ask::Tool).new)
      msgs.size.should eq 2
      t = msgs[0]
      t.should be_a(Ask::TextMessage)
      t.as(Ask::TextMessage).text.should eq "2+2"
      t = msgs[1]
      t.should be_a(Ask::TextMessage)
      t.as(Ask::TextMessage).text.should eq "4+4"
    end
  end

  it "should convert messages with restart" do
    tempdir do |dn|
      File.write "01q", "2+2"
      File.write "02q", "3+3"
      File.write "question", "4+4"
      File.write ".restart", "5"
      cl = Ask::ConversationEntries.new
      l = cl.entries_from_disk
      l.size.should eq 1
      msgs = cl.to_messages(Array(Ask::Tool).new)
      msgs.size.should eq 1
      t = msgs[0]
      t.should be_a(Ask::TextMessage)
      t.as(Ask::TextMessage).text.should eq "4+4"
      cl.add_messages [Ask::TextMessage.new(role: "assistant", text: "8")]
      cl.write
      cl = Ask::ConversationEntries.new
      l = cl.entries_from_disk
      l.size.should eq 2
      l[0].filename.should eq "05q"
      l[1].filename.should eq "06a"
      msgs = cl.to_messages(Array(Ask::Tool).new)
      msgs.size.should eq 2
      t = msgs[0]
      t.should be_a(Ask::TextMessage)
      t.as(Ask::TextMessage).text.should eq "4+4"
      t = msgs[1]
      t.should be_a(Ask::TextMessage)
      t.as(Ask::TextMessage).text.should eq "8"
      File.realpath("answer").should eq "#{dn}/06a"
      File.read("answer").should eq "8"
    end
  end

  it "should run a tool" do
    src = "#{__DIR__}/../tools/add"
    tempdir do |tools_dn|
      Dir.mkdir "#{tools_dn}/logs"
      Dir.mkdir "#{tools_dn}/tools"
      Dir.mkdir "#{tools_dn}/tools/add"
      Dir.children(src).each do |i|
        FileUtils.cp "#{src}/#{i}", "#{tools_dn}/tools/add/#{i}"
      end
      tempdir do |dn|
        File.write ".tools", %(
add: {}
).strip
        File.write "m", %(
{"name":"add","parameters":{"b":123,"a":456},"id":""}
).strip
        c = Ask::Cli.new tools_dir: "#{tools_dn}/tools", tools_log_dir: "#{tools_dn}/logs"
        t = c.get_enabled_tools
        cl = Ask::ConversationEntries.new
        # simulate response from teh ai to call the add tool
        response = Array(Ask::Message).new
        response << Ask::ToolCallMessage.new(File.read("m"))
        seen = 0
        continue = c.process_response(response: response, tools: t, stop_reason: Ask::StopReason::ToolCall) do |tool, args, schema|
          if tool.name == "add"
            seen += 1
            true
          else
            false
          end
        end
        seen.should eq 1
        continue.should eq true
        cl.add_messages response
        cl.write
        cl = Ask::ConversationEntries.new
        cl.entries_from_disk.size.should eq 2
        JSON.parse(File.read("02r"))["response"].as_i.should eq 579
      end # tempdir
    end   # tools dn
  end     # it

end # describe
