# frozen_string_literal: true

module DiscordChatBridge
  class ChannelMapping < ActiveRecord::Base
    self.table_name = "discord_chat_bridge_channel_mappings"

    DIRECTIONS = %w[bidirectional discord_to_discourse discourse_to_discord].freeze
    SNOWFLAKE_FORMAT = /\A[1-9]\d{0,19}\z/.freeze

    belongs_to :chat_channel, class_name: "Chat::Channel"
    has_many :message_mappings,
             class_name: "DiscordChatBridge::MessageMapping",
             dependent: :restrict_with_error

    before_validation :normalize_identifiers

    validates :discord_guild_id,
              :discord_channel_id,
              :chat_channel_id,
              :activated_at,
              presence: true
    validates :discord_guild_id, :discord_channel_id, format: { with: SNOWFLAKE_FORMAT }
    validates :discord_webhook_id, format: { with: SNOWFLAKE_FORMAT }, allow_blank: true
    validates :direction, inclusion: { in: DIRECTIONS }
    validates :discord_channel_id,
              uniqueness: {
                conditions: -> { where(enabled: true) },
              },
              if: :enabled?
    validates :chat_channel_id,
              uniqueness: {
                conditions: -> { where(enabled: true) },
              },
              if: :enabled?
    validate :webhook_present_for_outbound
    validate :webhook_credentials_are_complete
    validate :enabled_mapping_is_not_archived
    validate :chat_channel_is_public
    validate :endpoints_are_immutable_after_messages_exist, on: :update

    scope :active, -> { where(enabled: true, archived_at: nil) }

    def inbound?
      enabled? && archived_at.nil? && direction.in?(%w[bidirectional discord_to_discourse])
    end

    def outbound?
      enabled? && archived_at.nil? && direction.in?(%w[bidirectional discourse_to_discord])
    end

    def webhook_configured?
      discord_webhook_id.present? && encrypted_discord_webhook_token.present?
    end

    def webhook_token
      return if encrypted_discord_webhook_token.blank?
      Encryption.decrypt(encrypted_discord_webhook_token)
    end

    def webhook_token=(token)
      self.encrypted_discord_webhook_token = token.present? ? Encryption.encrypt(token) : nil
    end

    def record_success!
      update_columns(
        last_success_at: Time.zone.now,
        last_error_at: nil,
        last_error_code: nil,
        last_error_message: nil,
      )
    end

    def record_error!(error)
      update_columns(
        last_error_at: Time.zone.now,
        last_error_code: error.class.name,
        last_error_message: error.message.to_s.first(500),
      )
    end

    private

    def normalize_identifiers
      self.discord_guild_id = discord_guild_id.to_s.strip.presence
      self.discord_channel_id = discord_channel_id.to_s.strip.presence
      self.discord_webhook_id = discord_webhook_id.to_s.strip.presence
    end

    def webhook_present_for_outbound
      return unless enabled? && direction.in?(%w[bidirectional discourse_to_discord])
      unless webhook_configured?
        errors.add(:base, "Discord webhook is required for outbound mappings")
      end
    end

    def webhook_credentials_are_complete
      id_present = discord_webhook_id.present?
      token_present = encrypted_discord_webhook_token.present?
      return if id_present == token_present

      errors.add(:base, "Discord webhook ID and token must be configured together")
    end

    def enabled_mapping_is_not_archived
      if enabled? && archived_at
        errors.add(:archived_at, "must be blank while the mapping is enabled")
      end
    end

    def chat_channel_is_public
      if chat_channel&.direct_message_channel?
        errors.add(:chat_channel, "must be a public category channel")
      end
    end

    def endpoints_are_immutable_after_messages_exist
      endpoints_changed =
        discord_guild_id_changed? || discord_channel_id_changed? || chat_channel_id_changed?
      return unless endpoints_changed && message_mappings.exists?

      errors.add(
        :base,
        "Channel endpoints cannot be changed after messages have been bridged; create a new mapping",
      )
    end
  end
end

# == Schema Information
#
# Table name: discord_chat_bridge_channel_mappings
#
#  id                              :bigint           not null, primary key
#  activated_at                    :datetime         not null
#  archived_at                     :datetime
#  direction                       :string           default("bidirectional"), not null
#  enabled                         :boolean          default(TRUE), not null
#  encrypted_discord_webhook_token :text
#  last_error_at                   :datetime
#  last_error_code                 :string
#  last_error_message              :text
#  last_success_at                 :datetime
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  chat_channel_id                 :bigint           not null
#  discord_channel_id              :string           not null
#  discord_guild_id                :string           not null
#  discord_webhook_id              :string
#
# Indexes
#
#  dcb_enabled_chat_channel_unique       (chat_channel_id) UNIQUE WHERE enabled
#  dcb_enabled_discord_channel_unique    (discord_channel_id) UNIQUE WHERE enabled
#  idx_on_discord_webhook_id_3d9633bb4a  (discord_webhook_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_channel_id => chat_channels.id) ON DELETE => restrict
#
