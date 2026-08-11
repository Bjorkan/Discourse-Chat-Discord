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
        build_avatar_url(payload["guild_id"], user_id, member["avatar"], author["avatar"])

      identity = Identity.find_or_initialize_by(discord_user_id: user_id)
      avatar_changed = identity.avatar_hash != avatar_hash || identity.avatar_url != avatar_url
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

      if avatar_changed && avatar_url.present?
        Jobs.enqueue(
          Jobs::DiscordChatBridge::CacheAvatar,
          identity_id: identity.id,
          avatar_url: avatar_url,
        )
      end
      identity
    end

    def self.build_avatar_url(guild_id, user_id, member_avatar, user_avatar)
      if guild_id.present? && member_avatar.present?
        "https://cdn.discordapp.com/guilds/#{guild_id}/users/#{user_id}/avatars/#{member_avatar}.png?size=128"
      elsif user_avatar.present?
        "https://cdn.discordapp.com/avatars/#{user_id}/#{user_avatar}.png?size=128"
      end
    end
    private_class_method :build_avatar_url
  end
end
