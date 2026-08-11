# frozen_string_literal: true

require "net/http"
require "json"

module DiscordChatBridge
  module Discord
    class Client
      API_BASE = "https://discord.com/api/v10"
      CONNECT_TIMEOUT = 5
      READ_TIMEOUT = 15

      def initialize(token: Credentials.bot_token, rate_limiter: RateLimiter.new)
        @token = token
        @rate_limiter = rate_limiter
      end

      def gateway_bot
        request(:get, "/gateway/bot", auth: true)
      end

      def current_user
        request(:get, "/users/@me", auth: true)
      end

      def message(channel_id, message_id)
        request(
          :get,
          "/channels/#{snowflake!(channel_id)}/messages/#{snowflake!(message_id)}",
          auth: true,
        )
      end

      def channel(channel_id)
        request(:get, "/channels/#{snowflake!(channel_id)}", auth: true)
      end

      def webhook(webhook_id:, token:)
        request(:get, "/webhooks/#{snowflake!(webhook_id)}/#{webhook_token!(token)}")
      end

      def execute_webhook(webhook_id:, token:, payload:, files: [])
        request(
          :post,
          "/webhooks/#{snowflake!(webhook_id)}/#{webhook_token!(token)}?wait=true",
          payload:,
          files:,
          ambiguous_on_timeout: true,
        )
      end

      def edit_webhook_message(webhook_id:, token:, message_id:, payload:, files: [])
        request(
          :patch,
          "/webhooks/#{snowflake!(webhook_id)}/#{webhook_token!(token)}/messages/#{snowflake!(message_id)}",
          payload:,
          files:,
        )
      end

      def delete_webhook_message(webhook_id:, token:, message_id:)
        request(
          :delete,
          "/webhooks/#{snowflake!(webhook_id)}/#{webhook_token!(token)}/messages/#{snowflake!(message_id)}",
          allow_not_found: true,
        )
      end

      private

      def request(
        method,
        path,
        payload: nil,
        files: [],
        auth: false,
        allow_not_found: false,
        ambiguous_on_timeout: false
      )
        raise PermanentError, "Discord bot token is not configured" if auth && @token.blank?

        uri = URI("#{API_BASE}#{path}")
        route_key = "#{method}:#{uri.path.gsub(%r{/messages/\d+}, "/messages/:id")}"
        attempts = 0

        begin
          loop do
            attempts += 1
            @rate_limiter.before_request(route_key)
            response = perform(method, uri, payload:, files:, auth:)
            @rate_limiter.update(route_key, response)
            body = parse_body(response)

            return nil if response.code.to_i == 404 && allow_not_found
            return body if response.code.to_i.between?(200, 299)

            if response.code.to_i == 429
              delay = @rate_limiter.rate_limited!(route_key, response, body || {})
              if attempts < 3
                sleep(delay)
                next
              end
              raise RetryableError.new("Discord rate limit persisted", retry_after: delay)
            end

            if response.code.to_i >= 500
              raise RetryableError, "Discord returned HTTP #{response.code}"
            end

            raise PermanentError,
                  "Discord returned HTTP #{response.code} (code #{body&.dig("code") || "unknown"})"
          end
        rescue Net::OpenTimeout, Errno::ECONNREFUSED, SocketError => error
          raise RetryableError, "Discord connection failed: #{error.class}"
        rescue Net::ReadTimeout, EOFError => error
          if ambiguous_on_timeout
            raise AmbiguousDeliveryError,
                  "Discord may have accepted the webhook request before #{error.class}"
          end
          raise RetryableError, "Discord response failed: #{error.class}"
        ensure
          files.each { |file| file[:io]&.close unless file[:io]&.closed? }
        end
      end

      def perform(method, uri, payload:, files:, auth:)
        request_class = Net::HTTP.const_get(method.to_s.capitalize)
        request = request_class.new(uri)
        request["Authorization"] = "Bot #{@token}" if auth
        request["User-Agent"] = "DiscourseDiscordChatBridge/1.0 (+#{Discourse.base_url})"

        if files.any?
          files.each { |file| file.fetch(:io).rewind }
          form = [["payload_json", JSON.generate(payload)]]
          files.each_with_index do |file, index|
            form << [
              "files[#{index}]",
              file.fetch(:io),
              { filename: file.fetch(:filename), content_type: file.fetch(:content_type) },
            ]
          end
          request.set_form(form, "multipart/form-data")
        elsif payload
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(payload)
        end

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: true,
          open_timeout: CONNECT_TIMEOUT,
          read_timeout: READ_TIMEOUT,
          write_timeout: READ_TIMEOUT,
        ) { |http| http.request(request) }
      end

      def parse_body(response)
        return nil if response.body.blank?
        JSON.parse(response.body)
      rescue JSON::ParserError
        nil
      end

      def snowflake!(value)
        string = value.to_s
        raise ArgumentError, "invalid Discord snowflake" unless string.match?(/\A\d+\z/)
        string
      end

      def webhook_token!(value)
        string = value.to_s
        unless string.match?(/\A[A-Za-z0-9._-]+\z/)
          raise ArgumentError, "invalid Discord webhook token"
        end
        string
      end
    end
  end
end
