# frozen_string_literal: true

RSpec.describe DiscordChatBridge::ThreadPreviewSerializerExtension do
  fab!(:chat_channel) { Fabricate(:chat_channel, threading_enabled: true) }
  fab!(:thread) { Fabricate(:chat_thread, channel: chat_channel) }
  fab!(:mapping) do
    Fabricate(:discord_chat_bridge_channel_mapping, chat_channel:)
  end

  before { ensure_bridge_actor }

  it "selects distinct external participants before applying the preview limit" do
    identities = 2.times.map { Fabricate(:discord_chat_bridge_identity) }
    identities.each_with_index do |identity, identity_index|
      message_count = identity_index.zero? ? 10 : 1
      message_count.times do
        message =
          Fabricate(
            :chat_message,
            chat_channel:,
            thread:,
            user: User.find(DiscordChatBridge::BRIDGE_USER_ID),
          )
        Fabricate(
          :discord_chat_bridge_message_mapping,
          channel_mapping: mapping,
          chat_message: message,
          discord_identity: identity,
          author_display_name: identity.display_name,
        )
      end
    end
    bridge_actor = User.find(DiscordChatBridge::BRIDGE_USER_ID)
    serializer =
      Chat::ThreadPreviewSerializer.new(
        thread,
        root: false,
        participants: {
          users: [bridge_actor.attributes],
          total_count: 1,
        },
      )

    expect(serializer.participant_users.map(&:id)).to contain_exactly(
      *identities.map(&:browser_user_id),
    )
    expect(serializer.participant_count).to eq(2)
  end
end
