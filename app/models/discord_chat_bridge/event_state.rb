# frozen_string_literal: true

module DiscordChatBridge
  class EventState < ActiveRecord::Base
    self.table_name = "discord_chat_bridge_event_states"

    validates :discord_channel_id, :discord_message_id, :latest_event_type, presence: true
    validates :discord_message_id, uniqueness: { scope: :discord_channel_id }
  end
end

# == Schema Information
#
# Table name: discord_chat_bridge_event_states
#
#  id                  :bigint           not null, primary key
#  discord_deleted_at  :datetime
#  gateway_sequence    :bigint
#  last_error          :text
#  latest_event_type   :string           not null
#  payload             :jsonb            not null
#  processed_at        :datetime
#  processing_attempts :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  discord_channel_id  :string           not null
#  discord_message_id  :string           not null
#  gateway_session_id  :string
#
# Indexes
#
#  dcb_event_message_unique                              (discord_channel_id,discord_message_id) UNIQUE
#  index_discord_chat_bridge_event_states_on_updated_at  (updated_at)
#
