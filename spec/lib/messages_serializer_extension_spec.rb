# frozen_string_literal: true

RSpec.describe DiscordChatBridge::MessagesSerializerExtension do
  fab!(:chat_channel)
  fab!(:bridge_actor) { ensure_bridge_actor }
  fab!(:message) { Fabricate(:chat_message, chat_channel:, user: bridge_actor) }
  fab!(:message_mapping) { Fabricate(:discord_chat_bridge_message_mapping, chat_message: message) }
  it "preloads bridge mappings and identities for a message collection" do
    collection = stub(messages: [message], thread_participants: nil, thread_memberships: nil)
    serializer = Chat::MessagesSerializer.new(collection, scope: Guardian.new, root: false)

    serializer.messages

    association = message.association(:discord_chat_bridge_message_mapping)
    expect(association).to be_loaded
    expect(association.target.association(:discord_identity)).to be_loaded
    expect(association.target).to eq(message_mapping)
  end
end
