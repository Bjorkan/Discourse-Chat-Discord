# frozen_string_literal: true

RSpec.describe DiscordChatBridge::AdminController do
  fab!(:admin)

  before { sign_in(admin) }

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
  end

  it "rejects non-staff access" do
    sign_in(Fabricate(:user))
    get "/discord-chat-bridge/admin.json"
    expect(response.status).to eq(404).or eq(403)
  end
end
