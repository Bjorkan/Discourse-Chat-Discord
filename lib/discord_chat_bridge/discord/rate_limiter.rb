# frozen_string_literal: true

module DiscordChatBridge
  module Discord
    class RateLimiter
      GLOBAL_KEY = "discord_chat_bridge:rest:global"
      MAX_BLOCKING_DELAY = 5

      def before_request(route_key)
        sleep_for_key(GLOBAL_KEY)
        bucket = Discourse.redis.get(bucket_route_key(route_key))
        sleep_for_key(bucket_key(bucket)) if bucket.present?
      end

      def update(route_key, response)
        bucket = response["X-RateLimit-Bucket"]
        Discourse.redis.set(bucket_route_key(route_key), bucket, ex: 1.day.to_i) if bucket.present?

        return unless response["X-RateLimit-Remaining"] == "0"
        delay = response["X-RateLimit-Reset-After"].to_f
        delay = 0.1 if delay <= 0
        Discourse.redis.set(
          bucket_key(bucket || route_key),
          monotonic_deadline(delay),
          px: (delay * 1000).ceil,
        )
      end

      def rate_limited!(route_key, response, body)
        delay = (body["retry_after"] || response["Retry-After"]).to_f
        delay = 1.0 if delay <= 0
        key =
          (
            if body["global"] || response["X-RateLimit-Global"] == "true"
              GLOBAL_KEY
            else
              bucket_key(response["X-RateLimit-Bucket"] || route_key)
            end
          )
        Discourse.redis.set(key, monotonic_deadline(delay), px: (delay * 1000).ceil)
        delay
      end

      private

      def bucket_route_key(route_key)
        "discord_chat_bridge:rest:route:#{Digest::SHA256.hexdigest(route_key)}"
      end

      def bucket_key(bucket)
        "discord_chat_bridge:rest:bucket:#{bucket}"
      end

      def monotonic_deadline(delay)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay
      end

      def sleep_for_key(key)
        ttl = Discourse.redis.pttl(key)
        return unless ttl.positive?

        delay = ttl / 1000.0
        if delay > MAX_BLOCKING_DELAY
          raise RetryableError.new("Discord rate limit is still active", retry_after: delay)
        end
        sleep(delay)
      end
    end
  end
end
