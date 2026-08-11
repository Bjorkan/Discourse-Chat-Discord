# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Discord::AttachmentUrl do
  it "accepts structured Discord CDN attachments" do
    expect(
      described_class.valid?("https://cdn.discordapp.com/attachments/1/2/file.png?ex=signed"),
    ).to eq(true)
  end

  it "rejects SSRF hosts, custom ports, userinfo, and unrelated CDN paths" do
    urls = %w[
      http://cdn.discordapp.com/attachments/1/2/a.png
      https://cdn.discordapp.com.evil.test/attachments/1/2/a.png
      https://127.0.0.1/attachments/1/2/a.png
      https://user@cdn.discordapp.com/attachments/1/2/a.png
      https://cdn.discordapp.com:444/attachments/1/2/a.png
      https://cdn.discordapp.com/avatars/1/a.png
    ]

    expect(urls).to all(satisfy { |url| !described_class.valid?(url) })
  end
end
