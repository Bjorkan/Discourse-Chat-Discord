# frozen_string_literal: true

module DiscordChatBridge
  module Inbound
    class ReconcileMessage
      def self.call(state_id)
        new(state_id).call
      end

      def initialize(state_id, client: Discord::Client.new)
        @state_id = state_id
        @client = client
      end

      def call
        state = EventState.find(@state_id)
        DistributedMutex.synchronize(lock_key(state), validity: 5.minutes) do
          reconcile(state.reload)
        end
      rescue => error
        EventState.where(id: @state_id).update_all(last_error: error.message.to_s.first(500))
        raise
      end

      private

      def reconcile(state)
        mapping = ChannelMapping.active.find_by(discord_channel_id: state.discord_channel_id)
        unless mapping&.inbound?
          state.update!(processed_at: Time.zone.now, last_error: nil)
          return
        end

        message_mapping =
          MessageMapping.find_by(
            discord_channel_id: state.discord_channel_id,
            discord_message_id: state.discord_message_id,
          )
        if message_mapping && message_mapping.channel_mapping_id != mapping.id
          state.update!(processed_at: Time.zone.now, last_error: nil)
          return
        end

        if message_mapping&.origin == "discourse"
          if state.discord_deleted_at && message_mapping.deleted_on_discord_at.blank?
            message_mapping.update!(deleted_on_discord_at: state.discord_deleted_at)
          end
          state.update!(processed_at: Time.zone.now, last_error: nil)
          return
        end

        if message_mapping&.deleted_on_discourse_at.present?
          state.update!(processed_at: Time.zone.now, last_error: nil)
          return
        end

        if state.discord_deleted_at
          delete_message(message_mapping, state)
        else
          payload = complete_payload(state)
          unless message_mapping || Filter.accept?(payload, mapping)
            state.update!(processed_at: Time.zone.now, last_error: nil)
            return
          end

          if message_mapping&.chat_message_id
            update_message(message_mapping, payload, state)
          else
            create_message(mapping, message_mapping, payload, state)
          end
        end

        state.update!(processed_at: Time.zone.now, last_error: nil)
        mapping.record_success!
      rescue PermanentError => error
        mapping&.record_error!(error)
        state.update!(processed_at: Time.zone.now, last_error: error.message.to_s.first(500))
      rescue => error
        mapping&.record_error!(error)
        raise
      end

      def complete_payload(state)
        payload = state.payload.to_h.except("_gateway_session_generation")
        complete =
          payload.dig("author", "id").present? && payload.key?("content") &&
            payload.key?("attachments")
        return payload if !payload.delete("_fetch_required") && complete

        fetched = @client.message(state.discord_channel_id, state.discord_message_id)
        Discord::EventNormalizer.call("MESSAGE_UPDATE", fetched).deep_merge(
          payload.except("_fetch_required"),
        )
      end

      def create_message(mapping, reservation, payload, state)
        identity = IdentityResolver.call(payload)
        attachment_result = AttachmentProcessor.new.call(payload["attachments"])
        raw = build_raw(payload["content"], attachment_result.markdown)
        reply_id = reply_chat_message_id(payload, mapping)
        actor = User.find(BRIDGE_USER_ID)

        MessageMapping.transaction do
          reservation ||=
            MessageMapping.create!(
              channel_mapping: mapping,
              discord_message_id: state.discord_message_id,
              discord_channel_id: state.discord_channel_id,
              discourse_chat_channel_id: mapping.chat_channel_id,
              origin: "discord",
              discord_identity: identity,
              delivery_status: "pending",
              author_display_name: identity.display_name,
              author_username: identity.discord_username,
              author_avatar_url: identity.avatar_template,
            )
          return if reservation.chat_message_id.present? || state.reload.discord_deleted_at

          previous_mapping = Thread.current[:discord_chat_bridge_mapping]
          Thread.current[:discord_chat_bridge_mapping] = reservation
          begin
            message =
              ChatSDK::Message.create(
                raw: raw,
                channel_id: mapping.chat_channel_id,
                guardian: Guardian.new(actor),
                in_reply_to_id: reply_id,
                upload_ids: attachment_result.upload_ids,
                enforce_membership: true,
              )
          ensure
            Thread.current[:discord_chat_bridge_mapping] = previous_mapping
          end
          reservation.update!(
            chat_message: message,
            delivery_status: "delivered",
            payload_digest: Formatting.digest(payload),
            discord_attachments: attachment_result.records,
            discourse_upload_ids: attachment_result.upload_ids,
          )
        end
      end

      def update_message(message_mapping, payload, state)
        return if message_mapping.deleted_on_discord_at.present?

        identity = IdentityResolver.call(payload)
        digest = Formatting.digest(payload)
        return if message_mapping.payload_digest == digest

        attachment_result =
          cached_attachment_result(message_mapping, payload["attachments"]) ||
            AttachmentProcessor.new.call(payload["attachments"])
        raw = build_raw(payload["content"], attachment_result.markdown)
        actor = User.find(BRIDGE_USER_ID)
        Chat::UpdateMessage.call!(
          guardian: Guardian.new(actor),
          params: {
            message_id: message_mapping.chat_message_id,
            channel_id: message_mapping.discourse_chat_channel_id,
            message: raw,
            upload_ids: attachment_result.upload_ids,
          },
        )
        message_mapping.update!(
          discord_identity: identity,
          author_display_name: identity.display_name,
          author_username: identity.discord_username,
          author_avatar_url: identity.avatar_template,
          discord_last_edited_at: parse_time(payload["edited_timestamp"]) || Time.zone.now,
          payload_digest: digest,
          discord_attachments: attachment_result.records,
          discourse_upload_ids: attachment_result.upload_ids,
        )
      rescue Service::Base::Failure => error
        raise PermanentError, "Discourse rejected Discord edit: #{error.context}"
      end

      def delete_message(message_mapping, state)
        return unless message_mapping
        return if message_mapping.deleted_on_discord_at.present?

        if message_mapping.chat_message_id &&
             (message = Chat::Message.with_deleted.find_by(id: message_mapping.chat_message_id)) &&
             message.deleted_at.blank?
          Chat::TrashMessage.call!(
            guardian: Guardian.new(User.find(BRIDGE_USER_ID)),
            params: {
              message_id: message.id,
              channel_id: message.chat_channel_id,
            },
          )
        end
        message_mapping.update!(
          deleted_on_discord_at: state.discord_deleted_at || Time.zone.now,
          delivery_status: "delivered",
        )
      rescue Service::Base::Failure => error
        raise PermanentError, "Discourse rejected Discord delete: #{error.context}"
      end

      def reply_chat_message_id(payload, mapping)
        discord_reply_id = payload.dig("message_reference", "message_id")
        return if discord_reply_id.blank?

        MessageMapping.find_by(
          discord_channel_id: mapping.discord_channel_id,
          discord_message_id: discord_reply_id,
        )&.chat_message_id
      end

      def build_raw(content, attachment_markdown)
        parts = [Formatting.discord_to_discourse(content), attachment_markdown].reject(&:blank?)
        raw = parts.join("\n\n")
        raw = "(Discord message contained no supported content)" if raw.blank?
        raw.first(SiteSetting.chat_maximum_message_length)
      end

      def cached_attachment_result(message_mapping, attachments)
        records = Array(message_mapping.discord_attachments)
        include_url = records.any? { |record| record["upload_id"].blank? }
        unless AttachmentProcessor.signature(records, include_url:) ==
                 AttachmentProcessor.signature(attachments, include_url:)
          return
        end

        upload_ids = records.filter_map { |record| record["upload_id"] }.map(&:to_i).uniq
        return if upload_ids.any?(&:zero?)
        return unless Upload.where(id: upload_ids).count == upload_ids.length

        AttachmentProcessor::Result.new(
          upload_ids:,
          markdown: records.filter_map { |record| record["markdown"].presence }.join("\n"),
          records:,
        )
      end

      def parse_time(value)
        Time.zone.parse(value) if value.present?
      rescue ArgumentError
        nil
      end

      def lock_key(state)
        "discord_chat_bridge:message:#{state.discord_channel_id}:#{state.discord_message_id}"
      end
    end
  end
end
