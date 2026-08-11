# frozen_string_literal: true

module DiscordChatBridge
  module Discord
    module AttachmentUrl
      HOSTS = %w[cdn.discordapp.com media.discordapp.net].freeze

      def self.valid?(url)
        uri = URI.parse(url.to_s)
        uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.fragment.nil? && uri.port == 443 &&
          HOSTS.include?(uri.host) && uri.path.start_with?("/attachments/")
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
