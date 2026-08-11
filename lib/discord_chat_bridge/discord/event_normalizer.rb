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
        referenced_message
      ].freeze
      AUTHOR_KEYS = %w[id username global_name avatar bot system].freeze
      MEMBER_KEYS = %w[nick avatar].freeze
      ATTACHMENT_KEYS = %w[id filename content_type size url proxy_url width height].freeze

      def self.call(event_type, payload)
        return payload.slice("id", "channel_id", "guild_id") if event_type == "MESSAGE_DELETE"
        return payload.slice("ids", "channel_id", "guild_id") if event_type == "MESSAGE_DELETE_BULK"

        normalized = payload.slice(*MESSAGE_KEYS)
        normalized["author"] = payload["author"].slice(*AUTHOR_KEYS) if payload.key?("author")
        normalized["member"] = payload["member"].slice(*MEMBER_KEYS) if payload.key?("member")
        if payload.key?("attachments")
          normalized["attachments"] = Array(payload["attachments"]).map do |item|
            item.slice(*ATTACHMENT_KEYS)
          end
        end
        normalized
      end
    end
  end
end
