# frozen_string_literal: true

module DiscordChatBridge
  class GatewayDemon < ::Demon::Base
    MAPPING_CHECK_INTERVAL = 15

    def self.prefix
      "discord_chat_bridge_gateway"
    end

    def stop_signal
      "TERM"
    end

    def stop_timeout
      20
    end

    def after_fork
      @stopping = false
      Signal.trap("TERM") { @stopping = true }
      Signal.trap("INT") { @stopping = true }

      until @stopping
        begin
          run_cycle
        rescue => error
          safe_health_update(
            connected: false,
            connecting: false,
            last_error: error.class.name,
            fatal: false,
          )
          Rails.logger.warn(
            "#{Log.prefix(operation: "cycle", direction: "gateway")} " \
              "result=restarting error_class=#{error.class}",
          )
          wait_until_stopping(5)
        end
      end
    end

    private

    def run_cycle
      if multisite?
        Health.update_gateway(
          connected: false,
          connecting: false,
          standby: false,
          waiting: false,
          fatal: true,
          last_error: "Discord Chat Bridge Gateway does not support multisite installations",
        )
        wait_until_stopping(30)
        return
      end

      unless runnable?
        Health.update_gateway(
          connected: false,
          connecting: false,
          standby: false,
          waiting: true,
          fatal: false,
        )
        wait_until_stopping(5)
        return
      end

      lease = Discord::LeaderLease.new
      unless lease.acquire
        Health.record_standby!
        wait_until_stopping(10)
        return
      end

      restart_delay = nil
      reconnect_request = Health.reconnect_request
      begin
        Health.update_gateway(
          connected: false,
          connecting: true,
          websocket_open: false,
          standby: false,
          waiting: false,
          fatal: false,
        )
        Discord::Gateway.new(
          stop_requested: -> { @stopping || !runnable? },
          lease_lost: -> { lease.lost },
        ).run
      rescue PermanentError => error
        Health.update_gateway(
          connected: false,
          connecting: false,
          last_error: error.message,
          fatal: true,
        )
        Rails.logger.error(
          "#{Log.prefix(operation: "run", direction: "gateway")} " \
            "result=fatal error_class=#{error.class}",
        )
        wait_until_fatal_cleared(reconnect_request)
      rescue RetryableError => error
        restart_delay = error.retry_after || 5
        Health.update_gateway(
          connected: false,
          connecting: false,
          waiting: true,
          last_error: error.message,
          retry_at: (Time.zone.now + restart_delay).iso8601,
          fatal: false,
        )
        Rails.logger.warn(
          "#{Log.prefix(operation: "run", direction: "gateway")} " \
            "result=waiting error_class=#{error.class}",
        )
      rescue => error
        Health.update_gateway(connected: false, last_error: error.class.name, fatal: false)
        Rails.logger.warn(
          "#{Log.prefix(operation: "run", direction: "gateway")} " \
            "result=restarting error_class=#{error.class}",
        )
        restart_delay = 5
      ensure
        lease.release
      end
      wait_until_stopping(restart_delay) if restart_delay
    end

    def wait_until_fatal_cleared(previous_reconnect_request)
      until @stopping || !runnable?
        current_reconnect_request = Health.reconnect_request
        break if current_reconnect_request.present? &&
          current_reconnect_request != previous_reconnect_request

        wait_until_stopping(1)
      end
    end

    def safe_health_update(**values)
      Health.update_gateway(**values)
    rescue StandardError
      nil
    end

    def wait_until_stopping(seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      until @stopping
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break unless remaining.positive?

        sleep([remaining, 0.5].min)
      end
    end

    def runnable?
      SiteSetting.chat_enabled && SiteSetting.discord_chat_bridge_enabled &&
        SiteSetting.discord_chat_bridge_gateway_autostart && Credentials.bot_token? &&
        DiscourseIntegration.compatible? && inbound_mapping?
    end

    def inbound_mapping?
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if @mapping_check_expires_at.blank? || now >= @mapping_check_expires_at
        @has_inbound_mapping = ChannelMapping.active.any?(&:inbound?)
        @mapping_check_expires_at = now + MAPPING_CHECK_INTERVAL
      end
      @has_inbound_mapping
    end

    def multisite?
      RailsMultisite::ConnectionManagement.all_dbs.many?
    end
  end
end
