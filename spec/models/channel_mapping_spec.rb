# frozen_string_literal: true

RSpec.describe DiscordChatBridge::ChannelMapping do
  it "enforces one active mapping per Discord channel" do
    first = Fabricate(:discord_chat_bridge_channel_mapping)
    duplicate =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        discord_channel_id: first.discord_channel_id,
      )

    expect(duplicate).not_to be_valid
  end

  it "enforces one active mapping per Chat channel" do
    first = Fabricate(:discord_chat_bridge_channel_mapping)
    duplicate =
      Fabricate.build(:discord_chat_bridge_channel_mapping, chat_channel: first.chat_channel)

    expect(duplicate).not_to be_valid
  end

  it "allows archived historical mappings" do
    first = Fabricate(:discord_chat_bridge_channel_mapping)
    first.update!(enabled: false, archived_at: Time.zone.now)

    expect(
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        discord_channel_id: first.discord_channel_id,
        chat_channel: first.chat_channel,
      ),
    ).to be_valid
  end

  it "requires a webhook only when outbound is enabled" do
    mapping =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        direction: "bidirectional",
        chat_channel: Fabricate(:chat_channel),
      )
    expect(mapping).not_to be_valid

    mapping.discord_webhook_id = "123"
    mapping.webhook_token = "secret-token"
    expect(mapping).to be_valid
    expect(mapping.encrypted_discord_webhook_token).not_to include("secret-token")
  end
end
