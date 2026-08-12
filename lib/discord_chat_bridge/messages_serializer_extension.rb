# frozen_string_literal: true

module DiscordChatBridge
  module MessagesSerializerExtension
    def messages
      bridge_messages =
        object.messages.flat_map do |message|
          [message, message.in_reply_to, message.thread&.original_message, message.thread&.last_message]
        end.compact.uniq(&:id)
      ActiveRecord::Associations::Preloader.new(
        records: bridge_messages,
        associations: {
          discord_chat_bridge_message_mapping: :discord_identity,
        },
      ).call
      super
    end
  end
end
