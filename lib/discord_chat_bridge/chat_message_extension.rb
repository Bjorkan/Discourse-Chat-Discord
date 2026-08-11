# frozen_string_literal: true

module DiscordChatBridge
  module ChatMessageExtension
    def discord_chat_bridge_mapping
      return @discord_chat_bridge_mapping if defined?(@discord_chat_bridge_mapping)
      unless user_id == BRIDGE_USER_ID
        @discord_chat_bridge_mapping = nil
        return
      end

      @discord_chat_bridge_mapping =
        MessageMapping.includes(:discord_identity).find_by(chat_message_id: id)
      if @discord_chat_bridge_mapping.blank?
        pending = Thread.current[:discord_chat_bridge_mapping]
        if pending&.discourse_chat_channel_id == chat_channel_id
          @discord_chat_bridge_mapping = pending
        end
      end
      @discord_chat_bridge_mapping
    end
  end
end
