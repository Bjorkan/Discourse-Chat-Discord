# frozen_string_literal: true

module DiscordChatBridge
  module Discord
    module EventNormalizer
      MESSAGE_KEYS = %w[
        id
        channel_id
        guild_id
        type
        content
        timestamp
        edited_timestamp
        webhook_id
        author
        member
        attachments
        message_reference
      ].freeze
      AUTHOR_KEYS = %w[id username global_name avatar bot system].freeze
      MEMBER_KEYS = %w[nick avatar].freeze
      ATTACHMENT_KEYS = %w[id filename content_type size url proxy_url width height].freeze

      def self.call(event_type, payload)
        return payload.slice("id", "channel_id", "guild_id") if event_type == "MESSAGE_DELETE"
        return payload.slice("ids", "channel_id", "guild_id") if event_type == "MESSAGE_DELETE_BULK"

        normalized = payload.slice(*MESSAGE_KEYS)
        author = payload["author"]
        member = payload["member"]
        normalized.delete("author")
        normalized.delete("member")
        normalized["author"] = author.slice(*AUTHOR_KEYS) if author.is_a?(Hash)
        normalized["member"] = member.slice(*MEMBER_KEYS) if member.is_a?(Hash)
        if payload.key?("attachments")
          normalized["attachments"] = Array(payload["attachments"]).filter_map do |item|
            item.slice(*ATTACHMENT_KEYS) if item.is_a?(Hash)
          end
        end
        normalized
      end
    end
  end
end
