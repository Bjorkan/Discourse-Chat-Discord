# frozen_string_literal: true

module DiscordChatBridge
  class ChannelMapping < ActiveRecord::Base
    self.table_name = "discord_chat_bridge_channel_mappings"

    DIRECTIONS = %w[bidirectional discord_to_discourse discourse_to_discord].freeze

    belongs_to :chat_channel, class_name: "Chat::Channel"
    has_many :message_mappings,
             class_name: "DiscordChatBridge::MessageMapping",
             dependent: :restrict_with_error

    validates :discord_guild_id, :discord_channel_id, :chat_channel_id, presence: true
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

    scope :active, -> { where(enabled: true, archived_at: nil) }

    def inbound?
      enabled? && direction.in?(%w[bidirectional discord_to_discourse])
    end

    def outbound?
      enabled? && direction.in?(%w[bidirectional discourse_to_discord])
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

    def webhook_present_for_outbound
      return unless enabled? && direction.in?(%w[bidirectional discourse_to_discord])
      unless webhook_configured?
        errors.add(:base, "Discord webhook is required for outbound mappings")
      end
    end
  end
end
