# frozen_string_literal: true

module DiscordChatBridge
  class EventState < ActiveRecord::Base
    self.table_name = "discord_chat_bridge_event_states"

    validates :discord_channel_id, :discord_message_id, :latest_event_type, presence: true
    validates :discord_message_id, uniqueness: { scope: :discord_channel_id }
  end
end
