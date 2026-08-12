# frozen_string_literal: true

module DiscordChatBridge
  module Health
    KEY = "discord_chat_bridge:gateway:health"
    SESSION_KEY = "discord_chat_bridge:gateway:session"
    RECONNECT_KEY = "discord_chat_bridge:gateway:reconnect"
    STANDBY_KEY = "discord_chat_bridge:gateway:standby"
    UPDATE_SCRIPT = <<~LUA
      local current = {}
      local existing = redis.call('get', KEYS[1])
      if existing then
        local decoded_ok, decoded = pcall(cjson.decode, existing)
        if decoded_ok and type(decoded) == 'table' then
          current = decoded
        end
      end

      local updates = cjson.decode(ARGV[1])
      for key, value in pairs(updates) do
        current[key] = value
      end

      local encoded = cjson.encode(current)
      redis.call('set', KEYS[1], encoded, 'EX', ARGV[2])
      return encoded
    LUA

    def self.gateway
      health = JSON.parse(Discourse.redis.get(KEY) || "{}")
      if (standby_seen_at = Discourse.redis.get(STANDBY_KEY)).present?
        health["standby_seen_at"] = standby_seen_at
        health["standby"] = !health["connected"]
        health["connected"] = false if health["connected"].nil?
      end
      health
    rescue JSON::ParserError
      {}
    end

    def self.update_gateway(**values)
      updates = values.stringify_keys.merge("updated_at" => Time.zone.now.iso8601)
      encoded =
        Discourse.redis.eval(
          UPDATE_SCRIPT,
          keys: [KEY],
          argv: [JSON.generate(updates), 5.minutes.to_i],
        )
      JSON.parse(encoded)
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

    def self.reconnect_request
      Discourse.redis.get(RECONNECT_KEY)
    end

    def self.record_standby!
      Discourse.redis.set(STANDBY_KEY, Time.zone.now.iso8601, ex: 30.seconds.to_i)
    end
  end
end
