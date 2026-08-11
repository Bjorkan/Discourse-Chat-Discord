# frozen_string_literal: true

RSpec.describe DiscordChatBridge::MessageSerializerExtension do
  fab!(:viewer, :user)

  before { ensure_bridge_actor }

  it "serializes explicit external identity and a stable browser-only grouping user" do
    identity =
      Fabricate(:discord_chat_bridge_identity, discord_user_id: "123", display_name: "Alice")
    mapping = Fabricate(:discord_chat_bridge_channel_mapping)
    message =
      Fabricate(
        :chat_message,
        chat_channel: mapping.chat_channel,
        user: User.find(DiscordChatBridge::BRIDGE_USER_ID),
      )
    Fabricate(
      :discord_chat_bridge_message_mapping,
      channel_mapping: mapping,
      chat_message: message,
      discord_identity: identity,
      author_display_name: "Alice",
      author_username: "alice",
    )

    json =
      Chat::MessageSerializer.new(message.reload, root: false, scope: Guardian.new(viewer)).as_json
    expect(json[:external_author]).to include(source: "discord", id: "123", display_name: "Alice")
    expect(json[:user][:id]).to eq(identity.browser_user_id)
    expect(json[:user][:id]).not_to eq(DiscordChatBridge::BRIDGE_USER_ID)
    expect(json[:user][:external]).to eq(true)
  end

  it "uses different grouping IDs for different Discord users and the same ID for one user" do
    one = Fabricate(:discord_chat_bridge_identity)
    two = Fabricate(:discord_chat_bridge_identity)

    expect(one.browser_user_id).not_to eq(two.browser_user_id)
    expect(one.browser_user_id).to eq(one.reload.browser_user_id)
  end

  it "leaves local Discourse messages unchanged" do
    message = Fabricate(:chat_message)
    json = Chat::MessageSerializer.new(message, root: false, scope: Guardian.new(viewer)).as_json

    expect(json).not_to have_key(:external_author)
    expect(json[:user][:id]).to eq(message.user_id)
  end

  it "uses the external author in thread original-message variants" do
    identity =
      Fabricate(:discord_chat_bridge_identity, discord_user_id: "999", display_name: "Thread Alice")
    channel = Fabricate(:chat_channel, threading_enabled: true)
    message =
      Fabricate(
        :chat_message,
        chat_channel: channel,
        user: User.find(DiscordChatBridge::BRIDGE_USER_ID),
      )
    mapping = Fabricate(:discord_chat_bridge_channel_mapping, chat_channel: channel)
    Fabricate(
      :discord_chat_bridge_message_mapping,
      channel_mapping: mapping,
      chat_message: message,
      discord_identity: identity,
      author_display_name: "Thread Alice",
    )

    json = Chat::ThreadOriginalMessageSerializer.new(message, root: false).as_json
    expect(json[:user][:id]).to eq(identity.browser_user_id)
    expect(json[:external_author][:display_name]).to eq("Thread Alice")
  end
end
