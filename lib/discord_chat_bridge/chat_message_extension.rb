# frozen_string_literal: true

module DiscordChatBridge
  module ChatMessageExtension
    def self.prepended(base)
      base.has_one :discord_chat_bridge_message_mapping,
                   class_name: "DiscordChatBridge::MessageMapping",
                   foreign_key: :chat_message_id,
                   inverse_of: :chat_message
    end

    def discord_chat_bridge_mapping
      return @discord_chat_bridge_mapping if defined?(@discord_chat_bridge_mapping)
      unless user_id == BRIDGE_USER_ID
        @discord_chat_bridge_mapping = nil
        return
      end

      @discord_chat_bridge_mapping = discord_chat_bridge_message_mapping
      @discord_chat_bridge_mapping&.discord_identity
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
