# frozen_string_literal: true

# name: discourse-discord-chat-bridge
# about: Bidirectional Discord and Discourse Chat bridge with external identity presentation
# version: 1.0.0
# authors: Discourse Discord Chat Bridge contributors
# url: https://github.com/example/discourse-discord-chat-bridge
# required_version: 3.5.0

gem "event_emitter", "0.2.6"
gem "mutex_m", "0.3.0"
gem "websocket", "1.2.11"
gem "websocket-client-simple", "0.9.0"

register_asset "stylesheets/discord-chat-bridge.scss"
register_svg_icon "discord"

add_admin_route(
  "discord_chat_bridge.admin.title",
  "discourse-discord-chat-bridge",
  use_new_show_route: true,
)

module ::DiscordChatBridge
  PLUGIN_NAME = "discourse-discord-chat-bridge"
  BRIDGE_USER_ID = -10_001
end

Rails.application.config.filter_parameters += %i[bot_token webhook_url discord_webhook_url]

require_relative "lib/discord_chat_bridge/engine"
require_relative "lib/discord_chat_bridge/errors"
require "demon/base"
require_relative "lib/discord_chat_bridge/gateway_demon"

register_demon_process DiscordChatBridge::GatewayDemon

after_initialize do
  register_seedfu_fixtures(Rails.root.join("plugins/discourse-discord-chat-bridge/db/fixtures"))

  %i[chat_message_created chat_message_edited chat_message_trashed].each do |event|
    on(event) do |message, _channel, _user, *_extra|
      next unless SiteSetting.discord_chat_bridge_enabled
      next if message.blank?

      operation =
        case event
        when :chat_message_created
          "create"
        when :chat_message_edited
          "update"
        else
          "delete"
        end

      Jobs.enqueue(
        Jobs::DiscordChatBridge::ProcessChatMessage,
        chat_message_id: message.id,
        operation:,
      )
    rescue => error
      Rails.logger.error(
        "#{DiscordChatBridge::Log.prefix(operation:, direction: "outbound")} enqueue_failed error_class=#{error.class}",
      )
    end
  end

  reloadable_patch do
    Chat::Message.prepend DiscordChatBridge::ChatMessageExtension
    Chat::MessageSerializer.prepend DiscordChatBridge::MessageSerializerExtension
    Chat::InReplyToSerializer.prepend DiscordChatBridge::InReplyToSerializerExtension
    Chat::ThreadOriginalMessageSerializer.prepend(
      DiscordChatBridge::ThreadOriginalMessageSerializerExtension,
    )
    Chat::ThreadPreviewSerializer.prepend(DiscordChatBridge::ThreadPreviewSerializerExtension)
  end

  Discourse::Application.routes.append do
    mount ::DiscordChatBridge::Engine, at: "/discord-chat-bridge"
  end
end
