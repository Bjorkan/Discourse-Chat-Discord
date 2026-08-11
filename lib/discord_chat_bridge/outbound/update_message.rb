# frozen_string_literal: true

module DiscordChatBridge
  module Outbound
    class UpdateMessage < Base
      def self.call(chat_message_id)
        new(chat_message_id).call
      end

      def call
        return unless eligible?
        message_mapping = existing_message_mapping
        unless message_mapping&.origin == "discourse" &&
                 message_mapping.delivery_status == "delivered"
          return
        end
        return if message_mapping.deleted_on_discord_at.present?

        value = content
        value =
          "#{value.first(1940)}\n\n[Edited message truncated; Discord limit is 2000 characters]" if value.length >
          2000
        current_upload_ids = message.upload_ids.sort
        attachments_changed =
          current_upload_ids != Array(message_mapping.discourse_upload_ids).map(&:to_i).sort
        files = attachments_changed ? upload_files.first(10) : []
        attachments =
          if attachments_changed
            files.each_with_index.map do |file, index|
              { id: index.to_s, filename: file[:filename] }
            end
          else
            attachments_for_edit(message_mapping)
          end
        payload = { content: value, allowed_mentions: ALLOWED_MENTIONS, attachments: attachments }
        digest = Formatting.digest(payload)
        return if message_mapping.payload_digest == digest

        response =
          @client.edit_webhook_message(
            webhook_id: mapping.discord_webhook_id,
            token: mapping.webhook_token,
            message_id: message_mapping.discord_message_id,
            payload: payload,
            files: files,
          )
        message_mapping.update!(
          discourse_last_edited_at: message.updated_at,
          payload_digest: digest,
          discord_attachments:
            Array(response["attachments"]).map { |item| item.slice("id", "filename") },
          discourse_upload_ids: current_upload_ids,
          last_error: nil,
        )
        mapping.record_success!
      rescue PermanentError => error
        mapping&.record_error!(error)
      rescue => error
        mapping&.record_error!(error)
        raise
      ensure
        cleanup_files(files || [])
      end
    end
  end
end
