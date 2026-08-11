# frozen_string_literal: true

module DiscordChatBridge
  module Outbound
    class DeleteMessage < Base
      def self.call(chat_message_id)
        new(chat_message_id).call
      end

      def call
        message_mapping = existing_message_mapping
        return unless message_mapping&.origin == "discourse"
        if message_mapping.delivery_status != "delivered" ||
             message_mapping.deleted_on_discord_at.present?
          return
        end

        channel_mapping = message_mapping.channel_mapping
        unless SiteSetting.discord_chat_bridge_enabled && channel_mapping.outbound? &&
                 channel_mapping.webhook_configured?
          return
        end

        @client.delete_webhook_message(
          webhook_id: channel_mapping.discord_webhook_id,
          token: channel_mapping.webhook_token,
          message_id: message_mapping.discord_message_id,
        )
        message_mapping.update!(
          deleted_on_discord_at: Time.zone.now,
          deleted_on_discourse_at: Time.zone.now,
          last_error: nil,
        )
        channel_mapping.record_success!
      rescue PermanentError => error
        message_mapping&.update_columns(last_error: error.message.to_s.first(500))
        channel_mapping&.record_error!(error)
      rescue => error
        message_mapping&.update_columns(last_error: error.message.to_s.first(500))
        channel_mapping&.record_error!(error)
        raise
      end
    end
  end
end
