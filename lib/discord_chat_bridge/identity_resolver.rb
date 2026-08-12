# frozen_string_literal: true

module DiscordChatBridge
  class IdentityResolver
    def self.call(payload)
      author = payload.fetch("author")
      member = payload["member"] || {}
      user_id = author.fetch("id").to_s
      username = author.fetch("username").to_s
      display_name = member["nick"].presence || author["global_name"].presence || username
      avatar_hash = member["avatar"].presence || author["avatar"].presence
      avatar_url =
        build_avatar_url(
          payload["guild_id"],
          user_id,
          member["avatar"],
          author["avatar"],
          author["discriminator"],
        )

      identity = Identity.find_or_initialize_by(discord_user_id: user_id)
      avatar_changed = identity.avatar_hash != avatar_hash || identity.avatar_url != avatar_url
      previous_avatar_upload_id = identity.avatar_upload_id if avatar_changed
      identity.avatar_upload = nil if avatar_changed
      identity.assign_attributes(
        discord_username: username,
        discord_global_name: author["global_name"],
        display_name: display_name,
        avatar_hash: avatar_hash,
        avatar_url: avatar_url,
        last_synced_at: Time.zone.now,
      )
      identity.save!

      if avatar_changed && avatar_url.present? && !avatar_url.include?("/embed/avatars/")
        Jobs.enqueue(
          Jobs::DiscordChatBridge::CacheAvatar,
          identity_id: identity.id,
          avatar_url: avatar_url,
          previous_avatar_upload_id:,
        )
      end
      identity
    end

    def self.build_avatar_url(guild_id, user_id, member_avatar, user_avatar, discriminator)
      if guild_id.present? && member_avatar.present?
        "https://cdn.discordapp.com/guilds/#{guild_id}/users/#{user_id}/avatars/#{member_avatar}.png?size=128"
      elsif user_avatar.present?
        "https://cdn.discordapp.com/avatars/#{user_id}/#{user_avatar}.png?size=128"
      else
        index =
          if discriminator.present? && discriminator != "0"
            discriminator.to_i % 5
          else
            (user_id.to_i >> 22) % 6
          end
        "https://cdn.discordapp.com/embed/avatars/#{index}.png"
      end
    end
    private_class_method :build_avatar_url
  end
end
