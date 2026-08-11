# frozen_string_literal: true

module DiscordChatBridge
  module Inbound
    module Filter
      SUPPORTED_MESSAGE_TYPES = [0, 19].freeze

      def self.accept?(payload, mapping)
        return false unless mapping&.inbound?
        return false if SUPPORTED_MESSAGE_TYPES.exclude?(payload["type"])

        webhook_id = payload["webhook_id"].to_s
        if webhook_id.present? &&
             ChannelMapping.active.where(discord_webhook_id: webhook_id).exists?
          return false
        end
        if webhook_id.present? && !SiteSetting.discord_chat_bridge_include_other_webhooks
          return false
        end

        author = payload["author"] || {}
        bot_user_id = Health.gateway["bot_user_id"].to_s
        return false if bot_user_id.present? && author["id"].to_s == bot_user_id
        return false if author["system"]
        return false if author["bot"] && !SiteSetting.discord_chat_bridge_include_bot_messages

        true
      end
    end
  end
end
