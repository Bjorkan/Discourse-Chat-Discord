# frozen_string_literal: true

module DiscordChatBridge
  ExternalUser =
    Data.define(:id, :username, :name, :avatar_template) do
      def can_chat = false
      def has_chat_enabled = false
      def user_option = nil
      def [](attribute) = attribute == :user ? nil : public_send(attribute)
      def read_attribute_for_serialization(attribute) = public_send(attribute)
    end

  module SerializerSupport
    def bridge_mapping
      object.discord_chat_bridge_mapping
    end

    def external_author
      mapping = bridge_mapping
      return unless mapping&.origin == "discord"

      identity = mapping.discord_identity
      {
        source: "discord",
        id: identity&.discord_user_id,
        display_name: mapping.author_display_name || identity&.display_name,
        username: mapping.author_username || identity&.discord_username,
        avatar_url: mapping.author_avatar_url || identity&.avatar_template,
        grouping_key: "discord:#{identity&.discord_user_id}",
      }
    end

    def external_user_json
      author = external_author
      return unless author

      identity = bridge_mapping.discord_identity
      return unless identity
      display_name = author[:display_name].presence || author[:username]
      {
        id: identity.browser_user_id,
        username: display_name,
        name: display_name,
        avatar_template: identity.avatar_template,
        can_chat: false,
        has_chat_enabled: false,
        primary_group_name: "discord-external",
        external: true,
      }
    end

    def external_user_object
      json = external_user_json
      return unless json

      ExternalUser.new(
        id: json[:id],
        username: json[:username],
        name: json[:name],
        avatar_template: json[:avatar_template],
      )
    end
  end
end
