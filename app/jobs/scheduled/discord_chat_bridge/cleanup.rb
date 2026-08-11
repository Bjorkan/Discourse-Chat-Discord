# frozen_string_literal: true

module Jobs
  module DiscordChatBridge
    class Cleanup < ::Jobs::Scheduled
      daily at: 3.hours

      def execute(_args)
        cutoff = SiteSetting.discord_chat_bridge_tombstone_retention_days.days.ago

        ::DiscordChatBridge::EventState.where("updated_at < ?", cutoff).delete_all
        ::DiscordChatBridge::MessageMapping
          .where(chat_message_id: nil)
          .where("updated_at < ?", cutoff)
          .where("deleted_on_discord_at IS NOT NULL OR deleted_on_discourse_at IS NOT NULL")
          .delete_all

        ::DiscordChatBridge::MessageMapping
          .where("updated_at < ?", cutoff)
          .where.not(chat_message_id: nil)
          .where.not(chat_message_id: Chat::Message.with_deleted.select(:id))
          .update_all(chat_message_id: nil, deleted_on_discourse_at: Time.zone.now)

        ::DiscordChatBridge::Identity
          .where("last_synced_at < ?", cutoff)
          .where.not(id: ::DiscordChatBridge::MessageMapping.select(:discord_identity_id))
          .delete_all
      end
    end
  end
end
