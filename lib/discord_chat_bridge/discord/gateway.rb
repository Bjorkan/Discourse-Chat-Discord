# frozen_string_literal: true

require "websocket-client-simple"
require "timeout"

module DiscordChatBridge
  module Discord
    class Gateway
      VERSION = 10
      INTENTS = (1 << 0) | (1 << 9) | (1 << 15)
      FATAL_CLOSE_CODES = [4004, 4010, 4011, 4012, 4013, 4014].freeze
      FRESH_SESSION_CLOSE_CODES = [4003, 4007, 4009].freeze
      CloseEvent = Data.define(:code)

      def initialize(client: Client.new, stop_requested: -> { false }, lease_lost: -> { false })
        @client = client
        @stop_requested = stop_requested
        @lease_lost = lease_lost
        @session = Health.session
        @backoff = 1.0
        @send_mutex = Mutex.new
        @last_reconnect_request = Discourse.redis.get(Health::RECONNECT_KEY)
      end

      def run
        until stopping?
          connect_once
          break if stopping?
          wait_until_stopping(@backoff + rand * [@backoff * 0.25, 2].min)
          @backoff = [@backoff * 2, 60].min
        end
      ensure
        safely_mark_disconnected
      end

      private

      def connect_once
        @closed = false
        @fatal_error = nil
        @heartbeat_thread = nil
        @heartbeat_acknowledged = true
        @hello_received = false
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @tls_mutex = Mutex.new
        @tls_condition = ConditionVariable.new
        @tls_verified = false

        url = gateway_url
        Timeout.timeout(15) do
          WebSocket::Client::Simple.connect(
            url,
            verify_mode: OpenSSL::SSL::VERIFY_PEER,
          ) do |websocket|
            @websocket = websocket
            register_callbacks(websocket)
          end
        end
        @websocket.instance_variable_get(:@socket).post_connection_check(URI(url).host)
        @tls_mutex.synchronize do
          @tls_verified = true
          @tls_condition.broadcast
        end
        start_lease_watchdog

        hello_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
        @mutex.synchronize do
          until @closed || stopping?
            @condition.wait(@mutex, 1)
            if !@hello_received && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= hello_deadline
              @fatal_error = RetryableError.new("Discord Gateway HELLO timed out")
              break
            end
          end
        end

        @websocket&.close unless @closed
        @heartbeat_thread&.kill
        @lease_watchdog&.kill
        raise @fatal_error if @fatal_error
      rescue StandardError
        @websocket&.close
        @heartbeat_thread&.kill
        @lease_watchdog&.kill
        raise
      end

      def register_callbacks(websocket)
        websocket.on(:message) { |event| guard_callback("message") { handle_frame(event) } }
        websocket.on(:error) { |event| guard_callback("error") { handle_error(event) } }
        websocket.on(:close) { |event| guard_callback("close") { handle_close(event) } }
        websocket.on(:open) do
          guard_callback("open") { Health.update_gateway(websocket_open: true) }
        end
      end

      # websocket-client-simple invokes these blocks on its own threads. An exception escaping a
      # callback would otherwise kill only that thread and leave the demon waiting forever.
      def guard_callback(source)
        yield
      rescue => error
        fail_connection(error, source:)
      end

      def handle_frame(event)
        @tls_mutex.synchronize do
          @tls_condition.wait(@tls_mutex, 15) unless @tls_verified
          return unless @tls_verified
        end

        if event.respond_to?(:type) && event.type == :close
          data = event.data.to_s.b
          code = data.bytesize >= 2 ? data.unpack1("n") : 0
          handle_close(CloseEvent.new(code:))
          @websocket&.close
        else
          handle_raw_message(event.data)
        end
      end

      def handle_raw_message(data)
        handle_payload(JSON.parse(data))
      rescue JSON::ParserError, TypeError => error
        Rails.logger.warn(
          "#{Log.prefix(operation: "decode", direction: "gateway")} error_class=#{error.class}",
        )
      end

      def handle_payload(payload)
        @session["sequence"] = payload["s"] if payload["s"]

        case payload["op"]
        when 0
          handle_dispatch(payload)
        when 1
          heartbeat(track_ack: false)
        when 7
          close_for_resume
        when 9
          unless payload["d"]
            @session = {}
            Health.clear_session
          end
          close_for_resume
        when 10
          @hello_received = true
          start_heartbeat(payload.dig("d", "heartbeat_interval"))
          resumable? ? resume : identify
        when 11
          @heartbeat_acknowledged = true
          Health.update_gateway(last_heartbeat_ack_at: Time.zone.now.iso8601)
        end
      rescue JSON::ParserError, TypeError => error
        Rails.logger.warn(
          "#{Log.prefix(operation: "decode", direction: "gateway")} error_class=#{error.class}",
        )
      end

      def handle_dispatch(payload)
        type = payload["t"]
        data = payload["d"] || {}

        case type
        when "READY"
          @session["session_id"] = data["session_id"]
          @session["resume_gateway_url"] = data["resume_gateway_url"]
          @session["bot_user_id"] = data.dig("user", "id")
          @backoff = 1.0
          persist_session
          Health.update_gateway(
            connected: true,
            connecting: false,
            websocket_open: true,
            session_resumable: true,
            bot_user_id: @session["bot_user_id"],
            last_error: nil,
            last_ready_at: Time.zone.now.iso8601,
          )
        when "RESUMED"
          @backoff = 1.0
          persist_session
          Health.update_gateway(
            connected: true,
            connecting: false,
            websocket_open: true,
            session_resumable: true,
            last_error: nil,
            last_resumed_at: Time.zone.now.iso8601,
          )
        when "MESSAGE_CREATE", "MESSAGE_UPDATE", "MESSAGE_DELETE", "MESSAGE_DELETE_BULK"
          enqueue_message_event(type, data, payload["s"])
        end

        persist_session if payload["s"]
        Health.update_gateway(last_event_at: Time.zone.now.iso8601, last_event_type: type)
      end

      def enqueue_message_event(type, data, sequence)
        channel_id = data["channel_id"].to_s
        return if inbound_channel_ids.exclude?(channel_id)

        Jobs.enqueue(
          Jobs::DiscordChatBridge::ProcessDiscordEvent,
          event_type: type,
          payload: EventNormalizer.call(type, data),
          gateway_sequence: sequence,
          gateway_session_id: @session["session_id"],
        )
      end

      def inbound_channel_ids
        if @channel_ids_expires_at.blank? ||
             @channel_ids_expires_at < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @inbound_channel_ids =
            ChannelMapping.active.select(&:inbound?).map(&:discord_channel_id).to_set
          @channel_ids_expires_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
        end
        @inbound_channel_ids
      end

      def start_heartbeat(interval_ms)
        unless interval_ms.to_f.positive?
          raise PermanentError, "Gateway HELLO omitted heartbeat interval"
        end

        interval = interval_ms / 1000.0
        @heartbeat_thread =
          Thread.new do
            sleep(interval * rand)
            until stopping? || @closed
              unless @heartbeat_acknowledged
                close_for_resume
                break
              end
              heartbeat
              sleep(interval)
              reconnect_if_requested
            end
          rescue => error
            fail_connection(error, source: "heartbeat")
          end
      end

      def start_lease_watchdog
        @lease_watchdog =
          Thread.new do
            until @closed
              sleep 1
              if stopping?
                close_for_resume
                break
              end
            end
          rescue => error
            fail_connection(error, source: "lease_watchdog")
          end
      end

      def heartbeat(track_ack: true)
        @heartbeat_acknowledged = false if track_ack
        send_payload(op: 1, d: @session["sequence"])
        Health.refresh_session
        Health.update_gateway(last_heartbeat_at: Time.zone.now.iso8601)
      end

      def identify
        send_payload(
          op: 2,
          d: {
            token: Credentials.bot_token,
            intents: INTENTS,
            properties: {
              os: RUBY_PLATFORM,
              browser: PLUGIN_NAME,
              device: PLUGIN_NAME,
            },
          },
        )
      end

      def resume
        send_payload(
          op: 6,
          d: {
            token: Credentials.bot_token,
            session_id: @session["session_id"],
            seq: @session["sequence"],
          },
        )
      end

      def send_payload(payload)
        @send_mutex.synchronize { @websocket.send(JSON.generate(payload)) }
      end

      def gateway_url
        base =
          if resumable?
            @session["resume_gateway_url"]
          else
            @client.gateway_bot.fetch("url")
          end
        uri = URI(base)
        valid_host = uri.host == "gateway.discord.gg" || uri.host&.end_with?(".discord.gg")
        unless uri.scheme == "wss" && valid_host && uri.userinfo.nil? && uri.port == 443 &&
                 uri.fragment.nil?
          raise PermanentError, "Discord returned an invalid Gateway URL"
        end
        uri.query = URI.encode_www_form(v: VERSION, encoding: "json")
        uri.to_s
      rescue URI::InvalidURIError
        raise PermanentError, "Discord returned an invalid Gateway URL"
      end

      def resumable?
        @session["session_id"].present? && @session["sequence"].present? &&
          @session["resume_gateway_url"].present?
      end

      def persist_session
        Health.save_session(
          @session.slice("session_id", "sequence", "resume_gateway_url", "bot_user_id"),
        )
      end

      def handle_close(event)
        code = event.respond_to?(:code) ? event.code.to_i : 0
        if FATAL_CLOSE_CODES.include?(code)
          @fatal_error = PermanentError.new("Discord Gateway closed with fatal code #{code}")
        elsif FRESH_SESSION_CLOSE_CODES.include?(code)
          @session = {}
          Health.clear_session
        end
        signal_closed
      end

      def handle_error(event)
        error_class = event.respond_to?(:class) ? event.class : "GatewayError"
        Health.update_gateway(last_error: error_class.to_s)
        @websocket&.close
        signal_closed
      end

      def close_for_resume
        @websocket&.close
        signal_closed
      end

      def signal_closed
        @mutex.synchronize do
          @closed = true
          @condition.broadcast
        end
      end

      def fail_connection(error, source:)
        failure =
          if error.is_a?(PermanentError) || error.is_a?(RetryableError)
            error
          else
            RetryableError.new("Discord Gateway #{source} failed: #{error.class}")
          end
        @mutex.synchronize do
          @fatal_error ||= failure
          @closed = true
          @condition.broadcast
        end
        Rails.logger.warn(
          "#{Log.prefix(operation: source, direction: "gateway")} " \
            "result=connection_failed error_class=#{error.class}",
        )
        @websocket&.close
      rescue StandardError
        # The failure state is set before logging and closing, so secondary cleanup errors cannot
        # strand the main connection loop.
        nil
      end

      def reconnect_if_requested
        current = Discourse.redis.get(Health::RECONNECT_KEY)
        return if current.blank? || current == @last_reconnect_request
        @last_reconnect_request = current
        close_for_resume
      end

      def stopping?
        @stop_requested.call || @lease_lost.call
      end

      def wait_until_stopping(seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        until stopping?
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break unless remaining.positive?

          sleep([remaining, 0.25].min)
        end
      end

      def safely_mark_disconnected
        Health.update_gateway(connected: false, connecting: false, websocket_open: false)
      rescue => error
        Rails.logger.warn(
          "#{Log.prefix(operation: "health", direction: "gateway")} " \
            "result=update_failed error_class=#{error.class}",
        )
      end
    end
  end
end
