# frozen_string_literal: true

module DiscordChatBridge
  module Discord
    module AvatarUrl
      HOST = "cdn.discordapp.com"
      SNOWFLAKE = "[1-9]\\d{0,19}"
      CUSTOM_PATH =
        %r{\A/(?:avatars/#{SNOWFLAKE}|guilds/#{SNOWFLAKE}/users/#{SNOWFLAKE}/avatars)/[A-Za-z0-9_]+\.png\z}
      DEFAULT_PATH = %r{\A/embed/avatars/[0-5]\.png\z}

      def self.valid?(url)
        uri = URI.parse(url.to_s)
        safe_origin =
          uri.is_a?(URI::HTTPS) && uri.host == HOST && uri.userinfo.nil? && uri.port == 443 &&
            uri.fragment.nil?
        safe_origin &&
          (
            (uri.path.match?(CUSTOM_PATH) && uri.query == "size=128") ||
              (uri.path.match?(DEFAULT_PATH) && uri.query.nil?)
          )
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
