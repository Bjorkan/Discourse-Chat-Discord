# frozen_string_literal: true

module DiscordChatBridge
  module Log
    def self.prefix(operation:, direction:, **fields)
      values = { plugin: PLUGIN_NAME, operation:, direction: }.merge(fields).compact
      values.map { |key, value| "#{key}=#{value.to_s.gsub(/\s+/, "_").first(200)}" }.join(" ")
    end
  end
end
