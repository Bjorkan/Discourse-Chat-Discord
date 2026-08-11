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

# == Schema Information
#
# Table name: discord_chat_bridge_message_mappings
#
#  id                        :bigint           not null, primary key
#  author_avatar_url         :string
#  author_display_name       :string
#  author_username           :string
#  deleted_on_discord_at     :datetime
#  deleted_on_discourse_at   :datetime
#  delivery_nonce            :string
#  delivery_status           :string           default("delivered"), not null
#  discord_attachments       :jsonb            not null
#  discord_last_edited_at    :datetime
#  discourse_last_edited_at  :datetime
#  discourse_upload_ids      :jsonb            not null
#  last_error                :text
#  origin                    :string           not null
#  payload_digest            :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  channel_mapping_id        :bigint           not null
#  chat_message_id           :bigint
#  discord_channel_id        :string           not null
#  discord_identity_id       :bigint
#  discord_message_id        :string           not null
#  discourse_chat_channel_id :bigint           not null
#
# Indexes
#
#  dcb_chat_message_unique                                        (chat_message_id) UNIQUE WHERE (chat_message_id IS NOT NULL)
#  dcb_discord_message_unique                                     (discord_channel_id,discord_message_id) UNIQUE
#  idx_on_discord_identity_id_09dddeae48                          (discord_identity_id)
#  index_discord_chat_bridge_message_mappings_on_delivery_status  (delivery_status)
#
# Foreign Keys
#
#  fk_rails_...  (channel_mapping_id => discord_chat_bridge_channel_mappings.id) ON DELETE => restrict
#  fk_rails_...  (chat_message_id => chat_messages.id) ON DELETE => nullify
#  fk_rails_...  (discord_identity_id => discord_chat_bridge_identities.id) ON DELETE => restrict
#
