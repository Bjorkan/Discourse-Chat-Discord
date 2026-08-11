# frozen_string_literal: true

module DiscordChatBridgeSpecHelper
  def ensure_bridge_actor
    User.find_or_create_by!(id: DiscordChatBridge::BRIDGE_USER_ID) do |user|
      user.username = "discord_chat_bridge"
      user.name = "Discord Chat Bridge"
      user.email = "discord-chat-bridge@localhost.invalid"
      user.active = true
      user.approved = true
      user.trust_level = TrustLevel[1]
    end
  end

  def discord_payload(id: "100", channel_id: "200", user_id: "300", content: "Hello", **overrides)
    {
      "id" => id,
      "channel_id" => channel_id,
      "guild_id" => "400",
      "type" => 0,
      "content" => content,
      "timestamp" => Time.zone.now.iso8601,
      "edited_timestamp" => nil,
      "author" => {
        "id" => user_id,
        "username" => "alice",
        "global_name" => "Alice",
        "avatar" => "avatarhash",
        "bot" => false,
      },
      "member" => {
        "nick" => nil,
      },
      "attachments" => [],
    }.deep_merge(overrides.stringify_keys)
  end
end

RSpec.configure { |config| config.include DiscordChatBridgeSpecHelper }
