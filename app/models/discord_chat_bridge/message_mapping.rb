# frozen_string_literal: true

module DiscordChatBridge
  class MessageMapping < ActiveRecord::Base
    self.table_name = "discord_chat_bridge_message_mappings"

    ORIGINS = %w[discord discourse].freeze
    DELIVERY_STATUSES = %w[pending delivered ambiguous failed].freeze

    belongs_to :channel_mapping, class_name: "DiscordChatBridge::ChannelMapping"
    belongs_to :chat_message, class_name: "Chat::Message", optional: true
    belongs_to :discord_identity, class_name: "DiscordChatBridge::Identity", optional: true

    validates :origin, inclusion: { in: ORIGINS }
    validates :delivery_status, inclusion: { in: DELIVERY_STATUSES }
    validates :discord_message_id, :discord_channel_id, :discourse_chat_channel_id, presence: true
    validates :discord_identity, presence: true, if: -> { origin == "discord" }
    validates :chat_message_id, uniqueness: true, allow_nil: true
    validates :discord_message_id, uniqueness: { scope: :discord_channel_id }

    scope :discord_origin, -> { where(origin: "discord") }
    scope :discourse_origin, -> { where(origin: "discourse") }
  end
end
