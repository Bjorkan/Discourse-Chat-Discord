# frozen_string_literal: true

module DiscordChatBridge
  module Encryption
    PURPOSE = "discord-chat-bridge-secrets-v1"

    def self.encrypt(value)
      encryptor.encrypt_and_sign(value, purpose: PURPOSE)
    end

    def self.decrypt(value)
      encryptor.decrypt_and_verify(value, purpose: PURPOSE)
    end

    def self.encryptor
      secret = GlobalSetting.secret_key_base.presence || Rails.application.secret_key_base
      raise I18n.t("discord_chat_bridge.errors.secret_key_missing") if secret.blank?

      key = ActiveSupport::KeyGenerator.new(secret).generate_key(PURPOSE, 32)
      ActiveSupport::MessageEncryptor.new(key)
    end
    private_class_method :encryptor
  end
end
