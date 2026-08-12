# frozen_string_literal: true

module DiscordChatBridge
  class AdminController < ::Admin::AdminController
    requires_plugin PLUGIN_NAME

    def index
      render json: status_payload
    end

    def credentials
      token_updated = params[:bot_token].present?
      Credentials.bot_token = params[:bot_token] if token_updated
      SiteSetting.discord_chat_bridge_enabled = params[:enabled] if params.key?(:enabled)
      Health.request_reconnect! if token_updated || params.key?(:enabled)
      render json: status_payload
    end

    def test
      if params[:mapping_id].present?
        mapping = ChannelMapping.find(params[:mapping_id])
        unless Chat::Channel.exists?(mapping.chat_channel_id)
          raise ArgumentError, "Discourse Chat channel no longer exists"
        end
        client = Discord::Client.new
        channel = nil
        if mapping.inbound?
          channel = client.channel(mapping.discord_channel_id)
          validate_remote_guild!(channel, mapping)
        end
        webhook = nil
        if mapping.outbound?
          unless mapping.webhook_configured?
            raise ArgumentError, "Discord webhook is not configured"
          end
          webhook = validate_remote_webhook!(mapping, client:)
        end
        render json: {
                 ok: true,
                 channel: {
                   id: channel&.dig("id") || webhook&.dig("channel_id"),
                   name: channel&.dig("name"),
                 },
               }
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
      mapping.activated_at = Time.zone.now
      raise ActiveRecord::RecordInvalid, mapping unless mapping.valid?
      validate_remote_webhook!(mapping) if mapping.webhook_configured?
      mapping.save!
      render json: { mapping: serialize_mapping(mapping) }
    rescue ActiveRecord::RecordInvalid,
           ActiveRecord::RecordNotUnique,
           ArgumentError,
           PermanentError => error
      render_json_error safe_error(error), status: 422
    end

    def update_mapping
      mapping = ChannelMapping.find(params[:id])
      mapping.assign_attributes(mapping_attributes)
      apply_webhook(mapping)
      reactivating = mapping.enabled_changed?(from: false, to: true)
      mapping.archived_at = nil if reactivating
      if should_validate_webhook?(mapping)
        raise ActiveRecord::RecordInvalid, mapping unless mapping.valid?
        validate_remote_webhook!(mapping)
      end
      mapping.activated_at = Time.zone.now if reactivating
      mapping.save!
      render json: { mapping: serialize_mapping(mapping) }
    rescue ActiveRecord::RecordInvalid,
           ActiveRecord::RecordNotFound,
           ActiveRecord::RecordNotUnique,
           ArgumentError,
           PermanentError => error
      render_json_error safe_error(error), status: 422
    end

    def destroy_mapping
      mapping = ChannelMapping.find(params[:id])
      mapping.update!(enabled: false, archived_at: Time.zone.now)
      render json: { mapping: serialize_mapping(mapping) }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
      render_json_error safe_error(error), status: 422
    end

    private

    def status_payload
      gateway = Health.gateway
      mappings = ChannelMapping.order(:id).map { |mapping| serialize_mapping(mapping) }
      {
        enabled: SiteSetting.discord_chat_bridge_enabled,
        token_present: Credentials.bot_token?,
        token_managed_by_environment: ENV["DISCORD_CHAT_BRIDGE_BOT_TOKEN"].to_s.strip.present?,
        integration: {
          compatible: DiscourseIntegration.compatible?,
          chat_enabled: SiteSetting.chat_enabled,
          missing_constants: DiscourseIntegration.missing_constants,
        },
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
          mapping_errors:
            mappings.count { |mapping| mapping[:enabled] && mapping[:last_error_at].present? },
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
               uri.port == 443 && uri.query.nil? && uri.fragment.nil? && match
        raise ArgumentError, I18n.t("discord_chat_bridge.errors.invalid_webhook_url")
      end

      mapping.discord_webhook_id = match[1]
      mapping.webhook_token = match[2]
    rescue URI::InvalidURIError
      raise ArgumentError, I18n.t("discord_chat_bridge.errors.invalid_webhook_url")
    end

    def should_validate_webhook?(mapping)
      return false unless mapping.webhook_configured?
      return true if params[:webhook_url].present?
      return false unless mapping.outbound?

      mapping.discord_channel_id_changed? || mapping.direction_changed? || mapping.enabled_changed?
    end

    def validate_remote_webhook!(mapping, client: Discord::Client.new)
      webhook =
        client.webhook(
          webhook_id: mapping.discord_webhook_id,
          token: mapping.webhook_token,
        )
      if webhook["channel_id"].to_s != mapping.discord_channel_id.to_s
        raise ArgumentError, "Discord webhook belongs to a different channel"
      end
      validate_remote_guild!(webhook, mapping)
      webhook
    end

    def validate_remote_guild!(remote_resource, mapping)
      remote_guild_id = remote_resource["guild_id"].to_s
      return if remote_guild_id.blank? || remote_guild_id == mapping.discord_guild_id.to_s

      raise ArgumentError, "Discord channel belongs to a different guild"
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
        if error.is_a?(ActiveRecord::RecordNotUnique)
          "An enabled mapping already uses one of these channels"
        elsif error.respond_to?(:record)
          error.record.errors.full_messages.join(", ")
        else
          error.message.to_s
        end
      token = bot_token_for_filtering
      message = message.gsub(token, "[FILTERED]") if token.present?
      message.first(500)
    end

    def bot_token_for_filtering
      Credentials.bot_token
    rescue StandardError
      nil
    end
  end
end
