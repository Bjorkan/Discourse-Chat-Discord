# frozen_string_literal: true

module Jobs
  module DiscordChatBridge
    class ProcessChatMessage < ::Jobs::Base
      sidekiq_options retry: 10

      def execute(args)
        chat_message_id = args[:chat_message_id].to_i
        return if chat_message_id <= 0

        case args[:operation]
        when "create"
          ::DiscordChatBridge::Outbound::CreateMessage.call(chat_message_id)
        when "update"
          ::DiscordChatBridge::Outbound::UpdateMessage.call(chat_message_id)
        when "delete"
          ::DiscordChatBridge::Outbound::DeleteMessage.call(chat_message_id)
        end
      end
    end
  end
end
