# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Outbound::Base do
  it "passes the configured byte limit to Discourse's remote-store download API" do
    SiteSetting.discord_chat_bridge_max_attachment_mb = 20
    source = Tempfile.new(%w[remote-upload .txt])
    source.write("remote attachment")
    source.close

    upload =
      stub(
        filesize: File.size(source.path),
        original_filename: "notes.txt",
        content_type: "text/plain",
      )
    message = stub(id: 123, uploads: [upload])
    store = mock
    store.expects(:path_for).with(upload).returns(nil)
    store.expects(:download).with(upload, max_file_size_kb: 20.megabytes).returns(source.path)
    Discourse.stubs(:store).returns(store)

    outbound = described_class.new(123)
    outbound.stubs(:message).returns(message)
    files = outbound.send(:upload_files)

    expect(files.map { |file| file[:filename] }).to eq(["notes.txt"])
  ensure
    outbound&.send(:cleanup_files, files || [])
    source&.close!
  end

  it "fails the whole preparation when an attachment is unavailable" do
    SiteSetting.discord_chat_bridge_max_attachment_mb = 10
    upload =
      stub(
        id: 456,
        filesize: 100,
        original_filename: "missing.txt",
        content_type: "text/plain",
      )
    message = stub(id: 123, uploads: [upload])
    store = mock
    store.expects(:path_for).with(upload).returns(nil)
    store.expects(:download).with(upload, max_file_size_kb: 10.megabytes).returns(nil)
    Discourse.stubs(:store).returns(store)
    outbound = described_class.new(123)
    outbound.stubs(:message).returns(message)

    expect { outbound.send(:upload_files) }.to raise_error(
      DiscordChatBridge::RetryableError,
      "Attachment 456 is temporarily unavailable",
    )
  end

  it "rejects messages with more files than Discord accepts" do
    message = stub(id: 123, uploads: Array.new(11) { stub })
    outbound = described_class.new(123)
    outbound.stubs(:message).returns(message)

    expect { outbound.send(:upload_files) }.to raise_error(
      DiscordChatBridge::PermanentError,
      "Discord accepts at most 10 files for this message",
    )
  end

  it "rejects attachments that exceed the aggregate upload budget" do
    SiteSetting.discord_chat_bridge_max_attachment_mb = 10
    uploads = 2.times.map { |index| stub(id: index, filesize: 6.megabytes) }
    message = stub(id: 123, uploads: uploads)
    outbound = described_class.new(123)
    outbound.stubs(:message).returns(message)

    expect { outbound.send(:upload_files) }.to raise_error(
      DiscordChatBridge::PermanentError,
      "Attachments exceed the configured total Discord upload limit",
    )
  end

  it "does not discard the tenth upload to attach a long message" do
    message = stub(id: 123, uploads: Array.new(10) { stub })
    outbound = described_class.new(123)
    outbound.stubs(:message).returns(message)
    outbound.stubs(:content).returns("x" * 2_001)

    expect { outbound.send(:prepare_content_and_files) }.to raise_error(
      DiscordChatBridge::PermanentError,
      "Discord accepts at most 9 files for this message",
    )
  end
end
