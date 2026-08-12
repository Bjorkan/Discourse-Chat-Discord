# frozen_string_literal: true

module Jobs
  module DiscordChatBridge
    class ProcessDiscordEvent < ::Jobs::Base
      sidekiq_options retry: 10

      def execute(args)
        @gateway_session_id = args[:gateway_session_id].to_s.presence
        @gateway_session_generation = args[:gateway_session_generation]&.to_i
        event_type = args[:event_type]
        payload = args[:payload] || {}

        if event_type == "MESSAGE_DELETE_BULK"
          Array(payload["ids"]).each do |message_id|
            persist_and_reconcile(
              "MESSAGE_DELETE",
              payload.slice("channel_id", "guild_id").merge("id" => message_id),
              args[:gateway_sequence],
            )
          end
        else
          persist_and_reconcile(event_type, payload, args[:gateway_sequence])
        end
      end

      private

      def persist_and_reconcile(event_type, payload, sequence)
        channel_id = payload["channel_id"].to_s
        message_id = payload["id"].to_s
        return if channel_id.blank? || message_id.blank?

        state = upsert_state(event_type, payload, sequence)
        return unless state

        ::DiscordChatBridge::Inbound::ReconcileMessage.call(state.id)
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def upsert_state(event_type, payload, sequence)
        state =
          ::DiscordChatBridge::EventState.find_or_initialize_by(
            discord_channel_id: payload["channel_id"].to_s,
            discord_message_id: payload["id"].to_s,
          )

        state.with_lock do
          incoming_sequence = sequence&.to_i
          if state.persisted?
            stored_generation = state.payload["_gateway_session_generation"]&.to_i
            same_session = state.gateway_session_id == @gateway_session_id
            if stored_generation && @gateway_session_generation
              return nil if @gateway_session_generation < stored_generation
              same_session = @gateway_session_generation == stored_generation
            elsif stored_generation && !same_session
              return nil
            end
            if same_session && state.gateway_sequence && incoming_sequence &&
                 incoming_sequence < state.gateway_sequence
              return nil
            end
          end

          if event_type == "MESSAGE_CREATE"
            state.payload = payload
          elsif event_type == "MESSAGE_UPDATE"
            complete =
              payload.dig("author", "id").present? && payload.key?("content") &&
                payload.key?("attachments")
            state.payload =
              if complete
                payload
              else
                payload.merge("_fetch_required" => true)
              end
          end
          if @gateway_session_generation
            state.payload =
              state.payload.merge(
                "_gateway_session_generation" => @gateway_session_generation,
              )
          end
          state.latest_event_type = event_type
          state.gateway_sequence = incoming_sequence if incoming_sequence
          state.gateway_session_id = @gateway_session_id
          state.discord_deleted_at = Time.zone.now if event_type == "MESSAGE_DELETE"
          state.processing_attempts += 1
          state.save!
        end
        state
      end
    end
  end
end
