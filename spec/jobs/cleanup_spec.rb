# frozen_string_literal: true

RSpec.describe Jobs::DiscordChatBridge::Cleanup do
  it "removes unused identities even when local mappings have no Discord identity" do
    old_identity =
      Fabricate(
        :discord_chat_bridge_identity,
        last_synced_at: (SiteSetting.discord_chat_bridge_tombstone_retention_days + 1).days.ago,
      )
    channel_mapping = Fabricate(:discord_chat_bridge_channel_mapping)
    local_message = Fabricate(:chat_message, chat_channel: channel_mapping.chat_channel)
    DiscordChatBridge::MessageMapping.create!(
      channel_mapping: channel_mapping,
      chat_message: local_message,
      discord_message_id: "123456789",
      discord_channel_id: channel_mapping.discord_channel_id,
      discourse_chat_channel_id: channel_mapping.chat_channel_id,
      origin: "discourse",
      delivery_status: "delivered",
    )

    described_class.new.execute({})

    expect(DiscordChatBridge::Identity.exists?(old_identity.id)).to eq(false)
  end

  it "starts a fresh retention window when a missing Chat row becomes a tombstone" do
    channel_mapping = Fabricate(:discord_chat_bridge_channel_mapping)
    chat_message = Fabricate(:chat_message, chat_channel: channel_mapping.chat_channel)
    message_mapping =
      Fabricate(
        :discord_chat_bridge_message_mapping,
        channel_mapping: channel_mapping,
        chat_message: chat_message,
        updated_at: (SiteSetting.discord_chat_bridge_tombstone_retention_days + 1).days.ago,
      )
    chat_message.delete

    described_class.new.execute({})

    expect(message_mapping.reload.chat_message_id).to be_nil
    expect(message_mapping.deleted_on_discourse_at).to be_present
    expect(message_mapping.updated_at).to be_within(1.minute).of(Time.zone.now)

    described_class.new.execute({})
    expect(DiscordChatBridge::MessageMapping.exists?(message_mapping.id)).to eq(true)
  end
end
