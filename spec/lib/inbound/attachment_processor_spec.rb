# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Inbound::AttachmentProcessor do
  before { ensure_bridge_actor }

  it "sanitizes untrusted filenames before generating fallback Markdown" do
    result =
      described_class.new.call(
        [
          {
            "filename" => "](@admin)\n@all.txt",
            "url" => "https://example.com/private",
            "size" => 1,
          },
        ],
      )

    expect(result.markdown).not_to include("@admin", "@all", "\n")
    expect(result.upload_ids).to be_empty
    expect(result.records.first).to include(
      "filename" => "](@admin)\n@all.txt",
      "url" => "https://example.com/private",
      "markdown" => result.markdown,
    )
  end

  it "includes signed URLs only when comparing fallback attachment state" do
    first = {
      "id" => "1",
      "filename" => "notes.txt",
      "size" => 5,
      "url" => "https://cdn.discordapp.com/attachments/1/2/notes.txt?ex=old",
    }
    refreshed = first.merge("url" => "https://cdn.discordapp.com/attachments/1/2/notes.txt?ex=new")

    expect(described_class.signature([first])).to eq(described_class.signature([refreshed]))
    expect(described_class.signature([first], include_url: true)).not_to eq(
      described_class.signature([refreshed], include_url: true),
    )
  end
end
