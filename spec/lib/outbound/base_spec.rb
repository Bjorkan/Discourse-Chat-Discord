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
end
