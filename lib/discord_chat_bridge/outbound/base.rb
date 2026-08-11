# frozen_string_literal: true

module DiscordChatBridge
  module Outbound
    class Base
      ALLOWED_MENTIONS = { parse: [] }.freeze

      def initialize(chat_message_id, client: Discord::Client.new)
        @chat_message_id = chat_message_id
        @client = client
      end

      private

      def message
        @message ||=
          Chat::Message
            .with_deleted
            .includes(:user, :uploads, in_reply_to: :user)
            .find_by(id: @chat_message_id)
      end

      def mapping
        return unless message
        @mapping ||= ChannelMapping.active.find_by(chat_channel_id: message.chat_channel_id)
      end

      def existing_message_mapping
        @existing_message_mapping ||= MessageMapping.find_by(chat_message_id: @chat_message_id)
      end

      def eligible?
        return false unless SiteSetting.discord_chat_bridge_enabled
        return false unless message && mapping&.outbound? && mapping.webhook_configured?
        return false if message.deleted_at.present?
        return false if message.user_id == BRIDGE_USER_ID
        return false if existing_message_mapping&.origin == "discord"
        true
      end

      def content
        raw = Formatting.discourse_to_discord(message.message)
        raw = raw.gsub(%r{!?\[[^\]]*\]\(upload://[^)]+\)}, "").gsub(%r{upload://\S+}, "")
        context = reply_context
        raw = "#{context}\n\n#{raw}" if context.present?
        raw
      end

      def reply_context
        replied = message.in_reply_to
        return unless replied

        replied_mapping = MessageMapping.find_by(chat_message_id: replied.id)
        name =
          replied_mapping&.author_display_name.presence || replied.user&.name.presence ||
            replied.user&.username || "Unknown"
        excerpt = replied.build_excerpt.to_s.gsub(/\s+/, " ").first(120)
        jump =
          if replied_mapping&.discord_message_id.present? &&
               !replied_mapping.discord_message_id.start_with?("pending:")
            "https://discord.com/channels/#{mapping.discord_guild_id}/#{mapping.discord_channel_id}/#{replied_mapping.discord_message_id}"
          end
        label = jump ? "[#{name}](#{jump})" : name
        "↳ #{label}: #{excerpt}"
      end

      def visible_name
        (message.user.name.presence || message.user.username).to_s.first(80)
      end

      def avatar_url
        fallback = SiteSetting.discord_chat_bridge_avatar_fallback_url.presence
        template = message.user.avatar_template
        return fallback if template.blank?

        base = SiteSetting.discord_chat_bridge_public_base_url.presence || Discourse.base_url
        path = template.gsub("{size}", "128")
        URI.join("#{base}/", path.sub(%r{\A/}, "")).to_s
      rescue URI::InvalidURIError
        fallback
      end

      def prepare_content_and_files
        value = content
        files = upload_files.first(10)
        return value, files if value.length <= 2000

        tempfile = Tempfile.new(%w[discourse-chat-message .txt])
        tempfile.binmode
        tempfile.write(value)
        tempfile.rewind
        cleanup_files([files.pop]) if files.length == 10
        files << {
          io: tempfile,
          filename: "message.txt",
          content_type: "text/plain",
          temporary: true,
        }
        ["#{value.first(1850)}\n\n[Full message attached as message.txt]", files]
      end

      def upload_files
        max_bytes = SiteSetting.discord_chat_bridge_max_attachment_mb.megabytes
        message.uploads.filter_map do |upload|
          next if upload.filesize.to_i > max_bytes
          source_path =
            Discourse.store.path_for(upload) ||
              Discourse.store.download(upload, max_file_size_kb: max_bytes)
          next if source_path.blank? || !File.file?(source_path)

          tempfile = Tempfile.new(["discord-outbound", File.extname(upload.original_filename.to_s)])
          tempfile.binmode
          File.open(source_path, "rb") { |source| IO.copy_stream(source, tempfile, max_bytes + 1) }
          if tempfile.size > max_bytes
            tempfile.close!
            next
          end
          tempfile.rewind
          {
            io: tempfile,
            filename: File.basename(upload.original_filename.to_s).presence || "attachment",
            content_type: upload.content_type.presence || "application/octet-stream",
            temporary: true,
          }
        rescue => error
          Rails.logger.warn(
            "#{Log.prefix(operation: "attachment", direction: "outbound", chat_message_id: message.id)} result=skipped error_class=#{error.class}",
          )
          nil
        end
      end

      def cleanup_files(files)
        files.each do |file|
          file[:io]&.close! if file[:temporary] && file[:io].respond_to?(:close!)
        end
      end

      def attachments_for_edit(message_mapping)
        Array(message_mapping.discord_attachments).map { |item| item.slice("id", "filename") }
      end
    end
  end
end
