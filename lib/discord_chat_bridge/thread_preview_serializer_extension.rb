# frozen_string_literal: true

module DiscordChatBridge
  module ThreadPreviewSerializerExtension
    MAX_PARTICIPANTS = 10

    def last_reply_user
      external_user_for(object.last_message) || super
    end

    def participant_users
      original_users = super
      return original_users if original_users.none? { |user| user.id == BRIDGE_USER_ID }

      users = original_users.reject { |user| user.id == BRIDGE_USER_ID }
      available_slots = [MAX_PARTICIPANTS - users.length, 0].max
      scope = external_participant_scope
      identity_ids =
        scope
          .group(:discord_identity_id)
          .order(Arel.sql("MAX(chat_messages.created_at) DESC"))
          .limit(available_slots)
          .pluck(:discord_identity_id)
      latest_mappings =
        scope
          .where(discord_identity_id: identity_ids)
          .select(
            "DISTINCT ON (discord_chat_bridge_message_mappings.discord_identity_id) " \
              "discord_chat_bridge_message_mappings.*",
          )
          .reorder("discord_identity_id, chat_messages.created_at DESC")
          .preload(:discord_identity)
          .index_by(&:discord_identity_id)
      external_participants =
        identity_ids.filter_map do |identity_id|
          external_user_for_mapping(latest_mappings[identity_id])
        end
      users + external_participants
    end

    def participant_count
      count = super
      participants = @participants&.dig(:users) || []
      contains_bridge_actor =
        participants.any? do |participant|
          (participant[:id] || participant["id"]).to_i == BRIDGE_USER_ID
        end
      return count unless contains_bridge_actor

      count - 1 + external_participant_scope.distinct.count(:discord_identity_id)
    end

    private

    def external_user_for(message)
      mapping = message&.discord_chat_bridge_mapping
      external_user_for_mapping(mapping) if mapping&.origin == "discord"
    end

    def external_user_for_mapping(mapping)
      identity = mapping.discord_identity
      return unless identity

      ExternalUser.new(
        id: identity.browser_user_id,
        username: mapping.author_display_name.presence || identity.display_name,
        name: mapping.author_display_name.presence || identity.display_name,
        avatar_template: identity.avatar_template,
      )
    end

    def external_participant_scope
      MessageMapping
        .joins(:chat_message)
        .where(chat_messages: { thread_id: object.id, deleted_at: nil }, origin: "discord")
        .where.not(discord_identity_id: nil)
    end
  end
end
