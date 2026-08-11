# frozen_string_literal: true

module DiscordChatBridge
  module ThreadPreviewSerializerExtension
    def last_reply_user
      external_user_for(object.last_message) || super
    end

    def participant_users
      users = super.reject { |user| user.id == BRIDGE_USER_ID }
      external_participants =
        MessageMapping
          .includes(:discord_identity)
          .joins(:chat_message)
          .where(chat_messages: { thread_id: object.id }, origin: "discord")
          .filter_map { |mapping| external_user_for_mapping(mapping) }
          .uniq(&:id)
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
