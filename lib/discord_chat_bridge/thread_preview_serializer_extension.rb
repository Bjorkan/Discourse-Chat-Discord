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
      external_participants =
        MessageMapping
          .includes(:discord_identity)
          .joins(:chat_message)
          .where(chat_messages: { thread_id: object.id, deleted_at: nil }, origin: "discord")
          .where.not(discord_identity_id: nil)
          .order("chat_messages.created_at DESC")
          .limit(MAX_PARTICIPANTS)
          .filter_map { |mapping| external_user_for_mapping(mapping) }
          .uniq(&:id)
          .first(available_slots)
      users + external_participants
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
  end
end
