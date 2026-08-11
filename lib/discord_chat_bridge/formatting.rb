# frozen_string_literal: true

module DiscordChatBridge
  module Formatting
    DISCORD_CONTENT_LIMIT = 2_000
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
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
    end

    # Discord measures message limits in UTF-16 code units. Ruby's String#length counts
    # Unicode codepoints, which undercounts characters outside the BMP (such as emoji).
    def self.discord_length(value)
      value.to_s.encode("UTF-16LE").bytesize / 2
    end

    def self.truncate_for_discord(value, max_length)
      text = value.to_s
      return text if discord_length(text) <= max_length

      length = 0
      text
        .each_char
        .take_while do |character|
          character_length = discord_length(character)
          next false if length + character_length > max_length

          length += character_length
          true
        end
        .join
    end

    def self.canonicalize(value)
      case value
      when Hash
        value
          .deep_stringify_keys
          .sort_by { |key, _nested_value| key }
          .to_h { |key, nested_value| [key, canonicalize(nested_value)] }
      when Array
        value.map { |nested_value| canonicalize(nested_value) }
      else
        value
      end
    end
    private_class_method :canonicalize
  end
end
