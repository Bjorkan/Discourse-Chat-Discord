# frozen_string_literal: true

module DiscordChatBridge
  module Discord
    class LeaderLease
      KEY = "discord_chat_bridge:gateway:leader"
      TTL_MS = 30_000
      RENEW_EVERY = 10
      RENEW_SCRIPT = <<~LUA
        if redis.call('get', KEYS[1]) == ARGV[1] then
          return redis.call('pexpire', KEYS[1], ARGV[2])
        end
        return 0
      LUA
      RELEASE_SCRIPT = <<~LUA
        if redis.call('get', KEYS[1]) == ARGV[1] then
          return redis.call('del', KEYS[1])
        end
        return 0
      LUA

      attr_reader :lost

      def initialize
        @token = "#{Socket.gethostname}:#{Process.pid}:#{SecureRandom.hex(16)}"
        @lost = false
      end

      def acquire
        result = Discourse.redis.set(KEY, @token, nx: true, px: TTL_MS)
        start_renewal if result
        !!result
      end

      def release
        @renewal&.kill
        Discourse.redis.eval(
          RELEASE_SCRIPT,
          keys: [Discourse.redis.namespace_key(KEY)],
          argv: [@token],
        )
      rescue => error
        Rails.logger.warn(
          "#{Log.prefix(operation: "lease_release", direction: "gateway")} error_class=#{error.class}",
        )
      end

      private

      def start_renewal
        @renewal =
          Thread.new do
            loop do
              sleep RENEW_EVERY
              renewed =
                Discourse.redis.eval(
                  RENEW_SCRIPT,
                  keys: [Discourse.redis.namespace_key(KEY)],
                  argv: [@token, TTL_MS],
                )
              unless renewed == 1
                @lost = true
                break
              end
            end
          rescue StandardError
            @lost = true
          end
      end
    end
  end
end
