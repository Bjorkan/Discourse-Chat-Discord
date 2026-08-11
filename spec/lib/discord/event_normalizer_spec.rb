# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Discord::EventNormalizer do
  it "drops unneeded Gateway fields before enqueueing" do
    payload = discord_payload.merge("embeds" => [{ "large" => "value" }], "nonce" => "secret-ish")
    result = described_class.call("MESSAGE_CREATE", payload)

    expect(result).not_to have_key("embeds")
    expect(result).not_to have_key("nonce")
    expect(result.dig("author", "id")).to eq("300")
  end

  it "preserves omitted fields on partial updates" do
    result =
      described_class.call(
        "MESSAGE_UPDATE",
        { "id" => "100", "channel_id" => "200", "content" => "changed" },
      )

    expect(result).not_to have_key("author")
    expect(result).not_to have_key("attachments")
  end

  it "drops malformed nested objects instead of crashing the Gateway callback" do
    result =
      described_class.call(
        "MESSAGE_CREATE",
        discord_payload("author" => nil, "member" => "invalid", "attachments" => [nil, 1]),
      )

    expect(result).not_to have_key("author")
    expect(result).not_to have_key("member")
    expect(result["attachments"]).to eq([])
  end
end
