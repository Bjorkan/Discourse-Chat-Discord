# frozen_string_literal: true

module Jobs
  module DiscordChatBridge
    class CacheAvatar < ::Jobs::Base
      sidekiq_options retry: 5

      def execute(args)
        identity = ::DiscordChatBridge::Identity.find_by(id: args[:identity_id])
        return if identity.blank? || identity.avatar_url.blank?
        avatar_url = args[:avatar_url].presence || identity.avatar_url
        return unless identity.avatar_url == avatar_url
        return unless ::DiscordChatBridge::Discord::AvatarUrl.valid?(avatar_url)

        tempfile =
          FileHelper.download(
            avatar_url,
            max_file_size: 2.megabytes,
            tmp_file_name: "discord-avatar-#{identity.discord_user_id}",
            follow_redirect: false,
            read_timeout: 5,
            validate_uri: true,
          )
        return unless tempfile

        upload =
          UploadCreator.new(
            tempfile,
            "discord-avatar-#{identity.discord_user_id}.png",
            type: "avatar",
          ).create_for(::DiscordChatBridge::BRIDGE_USER_ID)
        if upload.persisted?
          identity.reload
          identity.update!(avatar_upload: upload) if identity.avatar_url == avatar_url
        end
      ensure
        tempfile&.close!
      end
    end
  end
end
