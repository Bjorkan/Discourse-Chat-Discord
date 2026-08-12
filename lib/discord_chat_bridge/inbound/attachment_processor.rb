# frozen_string_literal: true

module DiscordChatBridge
  module Inbound
    class AttachmentProcessor
      METADATA_KEYS = %w[id filename content_type size].freeze
      RECORD_KEYS = [*METADATA_KEYS, "url"].freeze
      Result = Data.define(:upload_ids, :markdown, :records)

      def self.signature(attachments, include_url: false)
        keys = include_url ? RECORD_KEYS : METADATA_KEYS
        Array(attachments).map { |attachment| attachment.to_h.slice(*keys) }
      end

      def initialize(actor: User.find(BRIDGE_USER_ID))
        @actor = actor
      end

      def call(attachments)
        attachments = Array(attachments)
        max_bytes = SiteSetting.discord_chat_bridge_max_attachment_mb.megabytes
        if attachments.sum { |attachment| attachment.to_h["size"].to_i } > max_bytes
          raise PermanentError, "Attachments exceed the configured total Discord download limit"
        end
        upload_ids = []
        markdown = []
        records = []

        attachments.each do |attachment|
          result = process(attachment)
          upload_ids << result[:upload].id if result[:upload]
          markdown << result[:markdown]
          records << attachment
            .to_h
            .slice(*RECORD_KEYS)
            .merge("upload_id" => result[:upload]&.id, "markdown" => result[:markdown])
        end

        Result.new(upload_ids:, markdown: markdown.compact.join("\n"), records:)
      end

      private

      def process(attachment)
        url = attachment["url"].to_s
        filename =
          FileHelper.sanitize_filename(attachment["filename"].to_s).presence || "attachment"
        max_bytes = SiteSetting.discord_chat_bridge_max_attachment_mb.megabytes

        unless Discord::AttachmentUrl.valid?(url)
          return fallback(filename, url, "invalid attachment URL")
        end
        if attachment["size"].to_i > max_bytes
          return fallback(filename, url, "attachment exceeds size limit")
        end

        tempfile =
          FileHelper.download(
            url,
            max_file_size: max_bytes,
            tmp_file_name: filename,
            follow_redirect: false,
            read_timeout: 10,
            validate_uri: true,
            retain_on_max_file_size_exceeded: false,
          )
        return fallback(filename, url, "attachment download failed") unless tempfile

        upload =
          UploadCreator.new(tempfile, filename, type: "chat-composer", origin: url).create_for(
            @actor.id,
          )
        return fallback(filename, url, "attachment type is not allowed") unless upload.persisted?

        image = attachment["content_type"].to_s.start_with?("image/")
        syntax =
          image ? "![#{filename}](#{upload.short_url})" : "[#{filename}](#{upload.short_url})"
        { upload:, markdown: syntax }
      rescue => error
        Rails.logger.warn(
          "#{Log.prefix(operation: "attachment", direction: "inbound")} result=fallback error_class=#{error.class}",
        )
        fallback(filename, url, "attachment import failed")
      ensure
        tempfile&.close!
      end

      def fallback(filename, url, reason)
        if Discord::AttachmentUrl.valid?(url)
          { upload: nil, markdown: "[#{filename}](#{url}) (#{reason})" }
        else
          { upload: nil, markdown: "#{filename} (#{reason})" }
        end
      end
    end
  end
end
