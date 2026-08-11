# frozen_string_literal: true

module DiscordChatBridge
  module Health
    KEY = "discord_chat_bridge:gateway:health"
    SESSION_KEY = "discord_chat_bridge:gateway:session"
    RECONNECT_KEY = "discord_chat_bridge:gateway:reconnect"

    def self.gateway
      JSON.parse(Discourse.redis.get(KEY) || "{}")
    rescue JSON::ParserError
      {}
    end

    def self.update_gateway(**values)
      current = gateway.merge(values.stringify_keys).merge("updated_at" => Time.zone.now.iso8601)
      Discourse.redis.set(KEY, JSON.generate(current), ex: 5.minutes.to_i)
      current
    end

    def self.session
      JSON.parse(Discourse.redis.get(SESSION_KEY) || "{}")
    rescue JSON::ParserError
      {}
    end

    def self.save_session(session)
      Discourse.redis.set(SESSION_KEY, JSON.generate(session), ex: 1.hour.to_i)
    end

    def self.clear_session
      Discourse.redis.del(SESSION_KEY)
    end

    def self.request_reconnect!
      Discourse.redis.set(RECONNECT_KEY, SecureRandom.uuid, ex: 5.minutes.to_i)
    end
  end
end
