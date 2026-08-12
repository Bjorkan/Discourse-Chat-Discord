# frozen_string_literal: true

module DiscordChatBridge
  module DiscourseIntegration
    PATCHES = {
      "Chat::Message" => "DiscordChatBridge::ChatMessageExtension",
      "Chat::MessageSerializer" => "DiscordChatBridge::MessageSerializerExtension",
      "Chat::MessagesSerializer" => "DiscordChatBridge::MessagesSerializerExtension",
      "Chat::InReplyToSerializer" => "DiscordChatBridge::InReplyToSerializerExtension",
      "Chat::ThreadOriginalMessageSerializer" =>
        "DiscordChatBridge::ThreadOriginalMessageSerializerExtension",
      "Chat::ThreadPreviewSerializer" => "DiscordChatBridge::ThreadPreviewSerializerExtension",
    }.freeze
    REQUIRED_CONSTANTS =
      (
        PATCHES.keys + %w[Chat::Channel ChatSDK::Message Chat::UpdateMessage Chat::TrashMessage]
      ).freeze

    def self.missing_constants(constants = REQUIRED_CONSTANTS)
      constants.select { |constant_name| constant_name.safe_constantize.nil? }
    end

    def self.compatible?
      missing_constants.empty?
    end

    def self.install_patches(patches: PATCHES, logger: Rails.logger)
      missing = []

      patches.each do |target_name, extension_name|
        target = target_name.safe_constantize
        extension = extension_name.safe_constantize
        unless target && extension
          missing << target_name
          next
        end

        target.prepend(extension) if target.ancestors.exclude?(extension)
      end

      if missing.any?
        logger.error(
          "#{Log.prefix(operation: "install", direction: "discourse")} " \
            "result=incompatible missing_constants=#{missing.join(",")}",
        )
      end

      missing
    end
  end
end
