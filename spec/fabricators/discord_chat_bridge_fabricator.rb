# frozen_string_literal: true

Fabricator(:discord_chat_bridge_channel_mapping, class_name: "DiscordChatBridge::ChannelMapping") do
  discord_guild_id { sequence(:discord_guild_id) { |i| "800#{i}" } }
  discord_channel_id { sequence(:discord_channel_id) { |i| "900#{i}" } }
  chat_channel { Fabricate(:chat_channel) }
  direction "discord_to_discourse"
  enabled true
  activated_at { Time.zone.now }
end

Fabricator(:discord_chat_bridge_identity, class_name: "DiscordChatBridge::Identity") do
  discord_user_id { sequence(:discord_user_id) { |i| "700#{i}" } }
  discord_username "alice"
  discord_global_name "Alice"
  display_name "Alice"
  last_synced_at { Time.zone.now }
end

Fabricator(:discord_chat_bridge_message_mapping, class_name: "DiscordChatBridge::MessageMapping") do
  channel_mapping { Fabricate(:discord_chat_bridge_channel_mapping) }
  chat_message do |attrs|
    Fabricate(:chat_message, chat_channel: attrs[:channel_mapping].chat_channel)
  end
  discord_message_id { sequence(:discord_message_id) { |i| "600#{i}" } }
  discord_channel_id { |attrs| attrs[:channel_mapping].discord_channel_id }
  discourse_chat_channel_id { |attrs| attrs[:channel_mapping].chat_channel_id }
  origin "discord"
  discord_identity { Fabricate(:discord_chat_bridge_identity) }
  delivery_status "delivered"
end
