# frozen_string_literal: true

module DiscordChatBridge
  module ChatMessageExtension
    def discord_chat_bridge_mapping
      return @discord_chat_bridge_mapping if defined?(@discord_chat_bridge_mapping)
      @discord_chat_bridge_mapping =
        MessageMapping.includes(:discord_identity).find_by(chat_message_id: id)
      if @discord_chat_bridge_mapping.blank? && user_id == BRIDGE_USER_ID
        pending = Thread.current[:discord_chat_bridge_mapping]
        if pending&.discourse_chat_channel_id == chat_channel_id
          @discord_chat_bridge_mapping = pending
        end
      end
      @discord_chat_bridge_mapping
    end
  end
end
