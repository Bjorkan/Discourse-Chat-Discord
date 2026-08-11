# frozen_string_literal: true

module DiscordChatBridge
  module Discord
    module AvatarUrl
      HOST = "cdn.discordapp.com"
      SNOWFLAKE = "[1-9]\\d{0,19}"
      PATH =
        %r{\A/(?:avatars/#{SNOWFLAKE}|guilds/#{SNOWFLAKE}/users/#{SNOWFLAKE}/avatars)/[A-Za-z0-9_]+\.png\z}

      def self.valid?(url)
        uri = URI.parse(url.to_s)
        uri.is_a?(URI::HTTPS) && uri.host == HOST && uri.userinfo.nil? && uri.port == 443 &&
          uri.path.match?(PATH) && uri.query == "size=128" && uri.fragment.nil?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
