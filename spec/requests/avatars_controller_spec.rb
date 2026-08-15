# frozen_string_literal: true

RSpec.describe DiscordChatBridge::AvatarsController do
  fab!(:identity, :discord_chat_bridge_identity)

  it "rejects avatar sizes above the supported cache range" do
    get "/discord-chat-bridge/avatar/#{identity.discord_user_id}/999999.png"

    expect(response.status).to eq(404)
  end
end
