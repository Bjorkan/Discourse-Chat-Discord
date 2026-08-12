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

  it "rejects invalid Discord identifiers and missing activation timestamps" do
    mapping = Fabricate.build(:discord_chat_bridge_channel_mapping)
    mapping.discord_channel_id = "not-a-snowflake"
    mapping.activated_at = nil

    expect(mapping).not_to be_valid
    expect(mapping.errors[:discord_channel_id]).to be_present
    expect(mapping.errors[:activated_at]).to be_present
  end

  it "rejects private Chat direct messages" do
    mapping =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        chat_channel: Fabricate(:direct_message_channel),
      )

    expect(mapping).not_to be_valid
    expect(mapping.errors[:chat_channel]).to include("must be a public category channel")
  end

  it "keeps channel endpoints immutable after messages have been bridged" do
    mapping = Fabricate(:discord_chat_bridge_channel_mapping)
    Fabricate(:discord_chat_bridge_message_mapping, channel_mapping: mapping)

    mapping.discord_channel_id = "987654321"

    expect(mapping).not_to be_valid
    expect(mapping.errors[:base]).to include(
      "Channel endpoints cannot be changed after messages have been bridged; create a new mapping",
    )
  end

  it "can record success without hiding an unresolved event error" do
    mapping = Fabricate(:discord_chat_bridge_channel_mapping)
    mapping.record_error!(DiscordChatBridge::PermanentError.new("lost message"))

    mapping.record_success!(clear_error: false)

    expect(mapping.reload).to have_attributes(
      last_success_at: be_present,
      last_error_message: "lost message",
    )
  end
end
