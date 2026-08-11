# frozen_string_literal: true

module DiscordChatBridge
  module Formatting
    SAFE_AT = "\uFF20"

    def self.discord_to_discourse(content)
      text = content.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      text = text.gsub(/<@!?(\d+)>/, "#{SAFE_AT}user-\\1")
      text = text.gsub(/<@&(\d+)>/, "#{SAFE_AT}role-\\1")
      text = text.gsub(/<#(\d+)>/, "#channel-\\1")
      text = text.gsub("@", SAFE_AT)
      text.gsub(/\|\|(.+?)\|\|/m, "[spoiler]\\1[/spoiler]")
    end

    def self.discourse_to_discord(content)
      content.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
    end

    def self.digest(payload)
      Digest::SHA256.hexdigest(JSON.generate(payload.deep_stringify_keys.sort.to_h))
    end
  end
end
