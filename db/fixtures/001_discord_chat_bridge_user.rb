# frozen_string_literal: true

user = User.find_or_initialize_by(id: DiscordChatBridge::BRIDGE_USER_ID)
if user.persisted? && user.username != "discord_chat_bridge"
  raise "User ID #{DiscordChatBridge::BRIDGE_USER_ID} is already owned by another plugin"
end
user.username = "discord_chat_bridge"
user.name = "Discord Chat Bridge"
user.email = "discord-chat-bridge@localhost.invalid"
user.active = true
user.approved = true
user.trust_level = TrustLevel[1]
user.save!(validate: false)
