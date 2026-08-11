# frozen_string_literal: true

module DiscordChatBridge
  module Outbound
    class CreateMessage < Base
      def self.call(chat_message_id)
        new(chat_message_id).call
      end

      def call
        return unless eligible?
        return if existing_message_mapping&.delivery_status.in?(%w[delivered ambiguous])

        nonce = existing_message_mapping&.delivery_nonce || SecureRandom.uuid
        message_mapping = reserve(nonce)
        value, files = prepare_content_and_files
        payload = {
          content: value,
          username: visible_name,
          avatar_url: avatar_url,
          allowed_mentions: ALLOWED_MENTIONS,
        }.compact

        message_mapping.update!(
          delivery_status: "ambiguous",
          last_error: "Webhook delivery is in progress; reconcile before retrying if interrupted",
        )
        response =
          @client.execute_webhook(
            webhook_id: mapping.discord_webhook_id,
            token: mapping.webhook_token,
            payload: payload,
            files: files,
          )
        message_mapping.update!(
          discord_message_id: response.fetch("id"),
          delivery_status: "delivered",
          payload_digest: Formatting.digest(payload),
          discord_attachments:
            Array(response["attachments"]).map { |item| item.slice("id", "filename") },
          discourse_upload_ids: message.upload_ids,
          last_error: nil,
        )
        mapping.record_success!
      rescue AmbiguousDeliveryError => error
        message_mapping&.update!(delivery_status: "ambiguous", last_error: error.message)
        mapping&.record_error!(error)
      rescue RetryableError => error
        message_mapping&.update!(delivery_status: "pending", last_error: error.message)
        mapping&.record_error!(error)
        raise
      rescue PermanentError => error
        message_mapping&.update!(delivery_status: "failed", last_error: error.message)
        mapping&.record_error!(error)
      rescue => error
        message_mapping&.update_columns(last_error: error.message.to_s.first(500))
        mapping&.record_error!(error)
        raise
      ensure
        cleanup_files(files || [])
      end

      private

      def reserve(nonce)
        existing_message_mapping ||
          MessageMapping.create!(
            channel_mapping: mapping,
            chat_message: message,
            discord_message_id: "pending:#{nonce}",
            discord_channel_id: mapping.discord_channel_id,
            discourse_chat_channel_id: message.chat_channel_id,
            origin: "discourse",
            delivery_status: "pending",
            delivery_nonce: nonce,
            discourse_last_edited_at: message.updated_at,
          )
      end
    end
  end
end
