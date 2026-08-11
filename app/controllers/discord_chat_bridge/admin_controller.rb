# frozen_string_literal: true

module DiscordChatBridge
  class AdminController < ::Admin::AdminController
    requires_plugin PLUGIN_NAME

    def index
      render json: status_payload
    end

    def credentials
      Credentials.bot_token = params[:bot_token] if params[:bot_token].present?
      SiteSetting.discord_chat_bridge_enabled = params[:enabled] if params.key?(:enabled)
      render json: status_payload
    end

    def test
      if params[:mapping_id].present?
        mapping = ChannelMapping.find(params[:mapping_id])
        unless Chat::Channel.exists?(mapping.chat_channel_id)
          raise ArgumentError, "Discourse Chat channel no longer exists"
        end
        channel = Discord::Client.new.channel(mapping.discord_channel_id)
        render json: { ok: true, channel: { id: channel["id"], name: channel["name"] } }
        return
      end

      bot = Discord::Client.new.current_user
      render json: { ok: true, bot: { id: bot["id"], username: bot["username"] } }
    rescue => error
      render_json_error safe_error(error), status: 422
    end

    def reconnect
      Health.request_reconnect!
      render json: { ok: true }
    end

    def create_mapping
      mapping = ChannelMapping.new(mapping_attributes)
      apply_webhook(mapping)
      validate_remote_webhook!(mapping) if mapping.webhook_configured?
      mapping.activated_at = Time.zone.now
      mapping.save!
      render json: { mapping: serialize_mapping(mapping) }
    rescue ActiveRecord::RecordInvalid, ArgumentError, PermanentError => error
      render_json_error safe_error(error), status: 422
    end

    def update_mapping
      mapping = ChannelMapping.find(params[:id])
      mapping.assign_attributes(mapping_attributes)
      apply_webhook(mapping)
      validate_remote_webhook!(mapping) if params[:webhook_url].present?
      mapping.activated_at = Time.zone.now if mapping.enabled_changed?(from: false, to: true)
      mapping.save!
      render json: { mapping: serialize_mapping(mapping) }
    rescue ActiveRecord::RecordInvalid,
           ActiveRecord::RecordNotFound,
           ArgumentError,
           PermanentError => error
      render_json_error safe_error(error), status: 422
    end

    def destroy_mapping
      mapping = ChannelMapping.find(params[:id])
      mapping.update!(enabled: false, archived_at: Time.zone.now)
      render json: success_json
    end

    private

    def status_payload
      gateway = Health.gateway
      mappings = ChannelMapping.order(:id).map { |mapping| serialize_mapping(mapping) }
      {
        enabled: SiteSetting.discord_chat_bridge_enabled,
        token_present: Credentials.bot_token?,
        token_managed_by_environment: ENV["DISCORD_CHAT_BRIDGE_BOT_TOKEN"].present?,
        gateway:
          gateway.slice(
            "connected",
            "connecting",
            "standby",
            "waiting",
            "session_resumable",
            "last_event_at",
            "last_event_type",
            "last_ready_at",
            "last_resumed_at",
            "last_heartbeat_ack_at",
            "last_error",
            "fatal",
            "updated_at",
          ),
        mappings: mappings,
        summary: {
          enabled_mappings: mappings.count { |mapping| mapping[:enabled] },
          mapping_errors: mappings.count { |mapping| mapping[:last_error_at].present? },
          ambiguous_deliveries: MessageMapping.where(delivery_status: "ambiguous").count,
        },
      }
    end

    def mapping_attributes
      params.permit(:discord_guild_id, :discord_channel_id, :chat_channel_id, :direction, :enabled)
    end

    def apply_webhook(mapping)
      return if params[:webhook_url].blank?

      uri = URI.parse(params[:webhook_url])
      match = uri.path.match(%r{\A/api(?:/v\d+)?/webhooks/(\d+)/([A-Za-z0-9._-]+)\z})
      unless uri.is_a?(URI::HTTPS) && uri.host == "discord.com" && uri.userinfo.nil? &&
               uri.port == 443 && match
        raise ArgumentError, I18n.t("discord_chat_bridge.errors.invalid_webhook_url")
      end

      mapping.discord_webhook_id = match[1]
      mapping.webhook_token = match[2]
    rescue URI::InvalidURIError
      raise ArgumentError, I18n.t("discord_chat_bridge.errors.invalid_webhook_url")
    end

    def validate_remote_webhook!(mapping)
      webhook =
        Discord::Client.new.webhook(
          webhook_id: mapping.discord_webhook_id,
          token: mapping.webhook_token,
        )
      if webhook["channel_id"].to_s != mapping.discord_channel_id.to_s
        raise ArgumentError, "Discord webhook belongs to a different channel"
      end
    end

    def serialize_mapping(mapping)
      {
        id: mapping.id,
        discord_guild_id: mapping.discord_guild_id,
        discord_channel_id: mapping.discord_channel_id,
        chat_channel_id: mapping.chat_channel_id,
        direction: mapping.direction,
        enabled: mapping.enabled,
        webhook_configured: mapping.webhook_configured?,
        discord_webhook_id: mapping.discord_webhook_id,
        activated_at: mapping.activated_at,
        archived_at: mapping.archived_at,
        last_success_at: mapping.last_success_at,
        last_error_at: mapping.last_error_at,
        last_error_code: mapping.last_error_code,
        last_error_message: mapping.last_error_message,
      }
    end

    def safe_error(error)
      message =
        if error.respond_to?(:record)
          error.record.errors.full_messages.join(", ")
        else
          error.message.to_s
        end
      token = Credentials.bot_token
      message = message.gsub(token, "[FILTERED]") if token.present?
      message.first(500)
    end
  end
end
