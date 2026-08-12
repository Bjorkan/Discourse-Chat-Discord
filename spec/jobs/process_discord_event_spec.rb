# frozen_string_literal: true

RSpec.describe Jobs::DiscordChatBridge::ProcessDiscordEvent do
  fab!(:channel, :chat_channel)
  fab!(:mapping) do
    Fabricate(
      :discord_chat_bridge_channel_mapping,
      chat_channel: channel,
      discord_channel_id: "200",
    )
  end

  before do
    SiteSetting.discord_chat_bridge_enabled = true
    SiteSetting.chat_enabled = true
    ensure_bridge_actor
  end

  def execute(type, payload, sequence, session_id = nil, session_generation = nil)
    described_class.new.execute(
      event_type: type,
      payload: payload,
      gateway_sequence: sequence,
      gateway_session_id: session_id,
      gateway_session_generation: session_generation,
    )
  end

  it "creates one genuine Chat message and one external identity" do
    execute("MESSAGE_CREATE", discord_payload, 1)

    bridge_mapping = DiscordChatBridge::MessageMapping.last
    expect(bridge_mapping.chat_message.user_id).to eq(DiscordChatBridge::BRIDGE_USER_ID)
    expect(bridge_mapping.discord_identity.display_name).to eq("Alice")
    expect(User.where(id: 300).or(User.where(username: "alice"))).to be_empty
  end

  it "is idempotent for duplicate creates" do
    2.times { execute("MESSAGE_CREATE", discord_payload, 1) }
    expect(DiscordChatBridge::MessageMapping.count).to eq(1)
    expect(Chat::Message.where(user_id: DiscordChatBridge::BRIDGE_USER_ID).count).to eq(1)
  end

  it "updates the existing Chat message for MESSAGE_UPDATE" do
    execute("MESSAGE_CREATE", discord_payload, 1)
    execute(
      "MESSAGE_UPDATE",
      discord_payload(:content => "Hello everyone", "edited_timestamp" => Time.zone.now.iso8601),
      2,
    )

    expect(DiscordChatBridge::MessageMapping.last.chat_message.reload.message).to eq(
      "Hello everyone",
    )
  end

  it "does not adopt historical messages when a Discord channel is remapped" do
    execute("MESSAGE_CREATE", discord_payload, 1)
    original_message = DiscordChatBridge::MessageMapping.last.chat_message
    mapping.update!(enabled: false, archived_at: Time.zone.now)
    replacement_channel = Fabricate(:chat_channel)
    Fabricate(
      :discord_chat_bridge_channel_mapping,
      chat_channel: replacement_channel,
      discord_channel_id: "200",
      direction: "discord_to_discourse",
    )

    execute("MESSAGE_UPDATE", discord_payload(content: "Wrong destination"), 2)

    expect(original_message.reload.message).to eq("Hello")
    expect(Chat::Message.where(chat_channel_id: replacement_channel.id)).to be_empty
    expect(DiscordChatBridge::EventState.last.processed_at).to be_present
  end

  it "reuses imported attachment state for a text-only edit" do
    payload =
      discord_payload(
        "attachments" => [
          {
            "id" => "attachment-1",
            "filename" => "notes.txt",
            "content_type" => "text/plain",
            "size" => 5,
            "url" => "https://cdn.discordapp.com/attachments/1/2/notes.txt",
          },
        ],
      )
    processor = DiscordChatBridge::Inbound::AttachmentProcessor.any_instance
    processor
      .expects(:call)
      .once
      .returns(
        DiscordChatBridge::Inbound::AttachmentProcessor::Result.new(
          upload_ids: [],
          markdown: "[notes.txt](https://cdn.discordapp.com/attachments/1/2/notes.txt)",
          records: [
            {
              "id" => "attachment-1",
              "filename" => "notes.txt",
              "content_type" => "text/plain",
              "size" => 5,
              "upload_id" => nil,
              "markdown" => "[notes.txt](https://cdn.discordapp.com/attachments/1/2/notes.txt)",
            },
          ],
        ),
      )

    execute("MESSAGE_CREATE", payload, 1)
    execute("MESSAGE_UPDATE", payload.merge("content" => "Edited text"), 2)

    expect(DiscordChatBridge::MessageMapping.last.discord_attachments).to be_present
  end

  it "fetches a full message for a partial update" do
    execute("MESSAGE_CREATE", discord_payload, 1)
    DiscordChatBridge::Discord::Client
      .any_instance
      .expects(:message)
      .returns(discord_payload(content: "Fetched edit"))
    execute("MESSAGE_UPDATE", { "id" => "100", "channel_id" => "200" }, 2)

    expect(DiscordChatBridge::MessageMapping.last.chat_message.reload.message).to eq("Fetched edit")
  end

  it "preserves guild identity fields from a partial update" do
    execute("MESSAGE_CREATE", discord_payload("member" => { "nick" => "Guild Alice" }), 1)
    DiscordChatBridge::Discord::Client
      .any_instance
      .expects(:message)
      .returns(discord_payload(content: "Fetched edit").except("member"))

    execute(
      "MESSAGE_UPDATE",
      {
        "id" => "100",
        "channel_id" => "200",
        "guild_id" => "400",
        "member" => {
          "nick" => "Renamed in guild",
          "avatar" => "guild-avatar",
        },
      },
      2,
    )

    expect(DiscordChatBridge::MessageMapping.last.reload).to have_attributes(
      author_display_name: "Renamed in guild",
      author_avatar_url:
        "https://cdn.discordapp.com/guilds/400/users/300/avatars/guild-avatar.png?size=128",
    )
  end

  it "trashes on delete and handles duplicate delete" do
    execute("MESSAGE_CREATE", discord_payload, 1)
    2.times { execute("MESSAGE_DELETE", { "id" => "100", "channel_id" => "200" }, 2) }

    bridge_mapping = DiscordChatBridge::MessageMapping.last
    expect(Chat::Message.with_deleted.find(bridge_mapping.chat_message_id).deleted_at).to be_present
    expect(bridge_mapping.deleted_on_discord_at).to be_present
  end

  it "handles bulk deletion" do
    execute("MESSAGE_CREATE", discord_payload(id: "100"), 1)
    execute("MESSAGE_CREATE", discord_payload(id: "101"), 2)
    execute(
      "MESSAGE_DELETE_BULK",
      { "ids" => %w[100 101], "channel_id" => "200", "guild_id" => "400" },
      3,
    )

    expect(DiscordChatBridge::MessageMapping.where.not(deleted_on_discord_at: nil).count).to eq(2)
  end

  it "ignores wrong channels, bots, own webhooks, and unsupported system messages" do
    execute("MESSAGE_CREATE", discord_payload(channel_id: "999"), 1)
    execute("MESSAGE_CREATE", discord_payload(:id => "101", "author" => { "bot" => true }), 2)
    mapping.webhook_token = "webhook-token"
    mapping.update!(discord_webhook_id: "555")
    execute("MESSAGE_CREATE", discord_payload(:id => "102", "webhook_id" => "555"), 3)
    execute("MESSAGE_CREATE", discord_payload(:id => "103", "type" => 7), 4)

    expect(DiscordChatBridge::MessageMapping.all).to be_empty
    expect(DiscordChatBridge::EventState.where(processed_at: nil)).to be_empty
  end

  it "uses nickname, then global name, and keeps identity stable through rename" do
    execute("MESSAGE_CREATE", discord_payload("member" => { "nick" => "Guild Alice" }), 1)
    execute(
      "MESSAGE_CREATE",
      discord_payload(
        :id => "101",
        :content => "Again",
        "author" => {
          "username" => "alice2",
          "global_name" => "Alice Cooper",
        },
      ),
      2,
    )

    expect(DiscordChatBridge::Identity.count).to eq(1)
    expect(DiscordChatBridge::Identity.last.display_name).to eq("Alice Cooper")
    expect(DiscordChatBridge::MessageMapping.first.author_display_name).to eq("Guild Alice")
  end

  it "uses Discord's default avatar for an author without a custom avatar" do
    execute("MESSAGE_CREATE", discord_payload("author" => { "avatar" => nil }), 1)

    expect(DiscordChatBridge::Identity.last.avatar_url).to eq(
      "https://cdn.discordapp.com/embed/avatars/0.png",
    )
  end

  it "creates native replies when the referenced message is mapped" do
    execute("MESSAGE_CREATE", discord_payload(id: "100"), 1)
    execute(
      "MESSAGE_CREATE",
      discord_payload(:id => "101", "message_reference" => { "message_id" => "100" }),
      2,
    )

    first, second = DiscordChatBridge::MessageMapping.order(:id)
    expect(second.chat_message.in_reply_to_id).to eq(first.chat_message_id)
  end

  it "degrades an unmapped reply to a normal message" do
    execute(
      "MESSAGE_CREATE",
      discord_payload("message_reference" => { "message_id" => "missing" }),
      1,
    )
    expect(DiscordChatBridge::MessageMapping.last.chat_message.in_reply_to_id).to be_nil
  end

  it "does not resurrect a message when delete is processed before an older create" do
    execute("MESSAGE_DELETE", { "id" => "100", "channel_id" => "200" }, 2)
    execute("MESSAGE_CREATE", discord_payload, 1)

    expect(DiscordChatBridge::MessageMapping.all).to be_empty
  end

  it "accepts a lower sequence after a fresh Gateway session" do
    execute("MESSAGE_CREATE", discord_payload, 100, "session-a", 1)
    execute("MESSAGE_UPDATE", discord_payload(content: "New session edit"), 1, "session-b", 2)

    expect(DiscordChatBridge::MessageMapping.last.chat_message.reload.message).to eq(
      "New session edit",
    )
  end

  it "rejects a delayed event from an older Gateway session" do
    execute("MESSAGE_CREATE", discord_payload, 100, "session-a", 1)
    execute("MESSAGE_UPDATE", discord_payload(content: "New session edit"), 1, "session-b", 2)
    execute("MESSAGE_UPDATE", discord_payload(content: "Delayed old edit"), 101, "session-a", 1)

    expect(DiscordChatBridge::MessageMapping.last.chat_message.reload.message).to eq(
      "New session edit",
    )
  end

  it "ignores Gateway lifecycle events for Discourse-origin webhook messages" do
    local = Fabricate(:chat_message, chat_channel: channel, message: "Local authority")
    DiscordChatBridge::MessageMapping.create!(
      channel_mapping: mapping,
      chat_message: local,
      discord_message_id: "100",
      discord_channel_id: "200",
      discourse_chat_channel_id: channel.id,
      origin: "discourse",
      delivery_status: "delivered",
    )

    execute("MESSAGE_DELETE", { "id" => "100", "channel_id" => "200" }, 1)
    expect(local.reload.deleted_at).to be_nil
    expect(DiscordChatBridge::MessageMapping.last.deleted_on_discord_at).to be_present
  end

  it "does not recreate a Chat-retention tombstone" do
    identity = Fabricate(:discord_chat_bridge_identity)
    DiscordChatBridge::MessageMapping.create!(
      channel_mapping: mapping,
      chat_message_id: nil,
      discord_message_id: "100",
      discord_channel_id: "200",
      discourse_chat_channel_id: channel.id,
      origin: "discord",
      discord_identity: identity,
      delivery_status: "delivered",
      deleted_on_discourse_at: Time.zone.now,
    )

    execute("MESSAGE_UPDATE", discord_payload(content: "Do not recreate"), 2)
    expect(DiscordChatBridge::MessageMapping.last.chat_message_id).to be_nil
  end

  it "neutralizes mentions before Chat processing" do
    execute("MESSAGE_CREATE", discord_payload(content: "@admin @all @here"), 1)
    message = DiscordChatBridge::MessageMapping.last.chat_message

    expect(message.message).not_to include("@admin", "@all", "@here")
    expect(message.user_mentions).to be_empty
  end
end
