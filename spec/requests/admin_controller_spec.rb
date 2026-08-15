# frozen_string_literal: true

RSpec.describe DiscordChatBridge::AdminController do
  fab!(:admin)

  before { sign_in(admin) }

  it "serves the custom admin route on a direct page load" do
    get "/admin/plugins/discourse-discord-chat-bridge/bridge"

    expect(response.status).to eq(200)
  end

  it "never returns stored bot or webhook tokens" do
    DiscordChatBridge::Credentials.bot_token = "super-secret-bot-token"
    mapping =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        direction: "bidirectional",
        discord_webhook_id: "123",
        chat_channel: Fabricate(:chat_channel),
      )
    mapping.webhook_token = "super-secret-webhook-token"
    mapping.save!

    get "/discord-chat-bridge/admin.json"

    expect(response.status).to eq(200)
    expect(response.body).not_to include("super-secret-bot-token", "super-secret-webhook-token")
    expect(response.parsed_body["token_present"]).to eq(true)
    expect(response.parsed_body["mappings"].first["webhook_configured"]).to eq(true)
    expect(response.parsed_body.dig("integration", "compatible")).to eq(true)
    expect(response.parsed_body.dig("integration", "missing_constants")).to eq([])
  end

  it "requests a Gateway reconnect when runtime credentials change" do
    DiscordChatBridge::Health.expects(:request_reconnect!)

    put "/discord-chat-bridge/admin/credentials.json", params: { bot_token: "new-token" }

    expect(response.status).to eq(200)
  end

  it "rejects non-staff access" do
    sign_in(Fabricate(:user))
    get "/discord-chat-bridge/admin.json"
    expect(response.status).to eq(404).or eq(403)
  end

  it "returns not found for a missing mapping" do
    post "/discord-chat-bridge/admin/test.json", params: { mapping_id: -1 }

    expect(response.status).to eq(404)
  end

  it "reactivates an archived mapping and verifies its stored outbound webhook" do
    mapping =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        direction: "discourse_to_discord",
        discord_webhook_id: "123",
        enabled: false,
        archived_at: Time.zone.now,
        chat_channel: Fabricate(:chat_channel),
      )
    mapping.webhook_token = "webhook-token"
    mapping.save!
    DiscordChatBridge::Discord::Client
      .any_instance
      .expects(:webhook)
      .returns({ "channel_id" => mapping.discord_channel_id })

    put "/discord-chat-bridge/admin/mappings/#{mapping.id}.json", params: { enabled: true }

    expect(response.status).to eq(200)
    expect(mapping.reload).to be_enabled
    expect(mapping.archived_at).to be_nil
  end

  it "rejects moving an outbound mapping when its stored webhook belongs to the old channel" do
    mapping =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        direction: "discourse_to_discord",
        discord_webhook_id: "123",
        chat_channel: Fabricate(:chat_channel),
      )
    mapping.webhook_token = "webhook-token"
    mapping.save!
    DiscordChatBridge::Discord::Client
      .any_instance
      .expects(:webhook)
      .returns({ "channel_id" => mapping.discord_channel_id })

    put "/discord-chat-bridge/admin/mappings/#{mapping.id}.json",
        params: {
          discord_channel_id: "987654321",
        }

    expect(response.status).to eq(422)
    expect(mapping.reload.discord_channel_id).not_to eq("987654321")
  end

  it "returns service unavailable when Discord cannot validate a new webhook" do
    chat_channel = Fabricate(:chat_channel)
    DiscordChatBridge::Discord::Client
      .any_instance
      .expects(:webhook)
      .raises(DiscordChatBridge::RetryableError, "Discord connection failed")

    post "/discord-chat-bridge/admin/mappings.json",
         params: {
           discord_guild_id: "400",
           discord_channel_id: "200",
           chat_channel_id: chat_channel.id,
           direction: "discourse_to_discord",
           enabled: true,
           webhook_url: "https://discord.com/api/webhooks/500/webhook-token",
         }

    expect(response.status).to eq(503)
    expect(DiscordChatBridge::ChannelMapping.where(chat_channel:)).to be_empty
  end

  it "rejects a mapping test when the Discord channel belongs to another guild" do
    mapping = Fabricate(:discord_chat_bridge_channel_mapping)
    DiscordChatBridge::Discord::Client
      .any_instance
      .expects(:channel)
      .returns({ "id" => mapping.discord_channel_id, "guild_id" => "987654321", "type" => 0 })

    post "/discord-chat-bridge/admin/test.json", params: { mapping_id: mapping.id }

    expect(response.status).to eq(422)
    expect(response.parsed_body["errors"]).to include(
      "Discord channel belongs to a different guild",
    )
  end

  it "rejects unsupported Discord channel types for inbound mappings" do
    chat_channel = Fabricate(:chat_channel)
    DiscordChatBridge::Discord::Client
      .any_instance
      .expects(:channel)
      .returns({ "id" => "200", "guild_id" => "400", "type" => 15 })

    post "/discord-chat-bridge/admin/mappings.json",
         params: {
           discord_guild_id: "400",
           discord_channel_id: "200",
           chat_channel_id: chat_channel.id,
           direction: "discord_to_discourse",
           enabled: true,
         }

    expect(response.status).to eq(422)
    expect(response.parsed_body["errors"]).to include("Discord channel type is not supported")
  end

  it "tests an outbound-only mapping without requiring bot channel access" do
    mapping =
      Fabricate(
        :discord_chat_bridge_channel_mapping,
        direction: "discourse_to_discord",
        discord_webhook_id: "123",
        webhook_token: "webhook-token",
      )
    client = DiscordChatBridge::Discord::Client.any_instance
    client.expects(:channel).never
    client.expects(:webhook).returns(
      { "channel_id" => mapping.discord_channel_id, "guild_id" => mapping.discord_guild_id },
    )

    post "/discord-chat-bridge/admin/test.json", params: { mapping_id: mapping.id }

    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("channel", "id")).to eq(mapping.discord_channel_id)
  end
end
