# frozen_string_literal: true

module DiscordChatBridge
  module Credentials
    STORE_KEY = "encrypted_bot_token"

    def self.bot_token
      return ENV["DISCORD_CHAT_BRIDGE_BOT_TOKEN"] if ENV["DISCORD_CHAT_BRIDGE_BOT_TOKEN"].present?

      encrypted = PluginStore.get(PLUGIN_NAME, STORE_KEY)
      Encryption.decrypt(encrypted) if encrypted.present?
    end

    def self.bot_token=(token)
      raise ArgumentError, "token must be present" if token.blank?
      PluginStore.set(PLUGIN_NAME, STORE_KEY, Encryption.encrypt(token.strip))
    end

    def self.bot_token?
      ENV["DISCORD_CHAT_BRIDGE_BOT_TOKEN"].present? ||
        PluginStore.get(PLUGIN_NAME, STORE_KEY).present?
    end
  end
end
