# frozen_string_literal: true

module Jobs
  module DiscordChatBridge
    class CacheAvatar < ::Jobs::Base
      sidekiq_options retry: 5

      def execute(args)
        identity = ::DiscordChatBridge::Identity.find_by(id: args[:identity_id])
        return if identity.blank? || identity.avatar_url.blank?
        if ::DiscordChatBridge::Discord::AttachmentUrl::HOSTS.exclude?(
             URI(identity.avatar_url).host,
           )
          return
        end

        tempfile =
          FileHelper.download(
            identity.avatar_url,
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
        identity.update!(avatar_upload: upload) if upload.persisted?
      ensure
        tempfile&.close!
      end
    end
  end
end
