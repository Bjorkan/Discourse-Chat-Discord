# frozen_string_literal: true

module DiscordChatBridge
  class GatewayDemon < ::Demon::Base
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
        unless runnable?
          Health.update_gateway(connected: false, connecting: false, waiting: true)
          sleep 5
          next
        end

        lease = Discord::LeaderLease.new
        unless lease.acquire
          Health.update_gateway(standby_seen_at: Time.zone.now.iso8601)
          sleep 10
          next
        end

        begin
          Health.update_gateway(connecting: true, standby: false, waiting: false)
          Discord::Gateway.new(
            stop_requested: -> { @stopping || !runnable? },
            lease_lost: -> { lease.lost },
          ).run
        rescue PermanentError => error
          Health.update_gateway(connected: false, last_error: error.message, fatal: true)
          Rails.logger.error(
            "#{Log.prefix(operation: "run", direction: "gateway")} result=fatal error_class=#{error.class}",
          )
          sleep 60 unless @stopping
        rescue => error
          Health.update_gateway(connected: false, last_error: error.class.name, fatal: false)
          Rails.logger.warn(
            "#{Log.prefix(operation: "run", direction: "gateway")} result=restarting error_class=#{error.class}",
          )
          sleep 5 unless @stopping
        ensure
          lease.release
        end
      end
    end

    private

    def runnable?
      SiteSetting.discord_chat_bridge_enabled &&
        SiteSetting.discord_chat_bridge_gateway_autostart && Credentials.bot_token? &&
        ChannelMapping.active.any?(&:inbound?)
    end
  end
end
