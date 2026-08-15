# frozen_string_literal: true

module DiscordChatBridge
  class AvatarsController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    skip_before_action :check_xhr

    def show
      identity = Identity.find_by!(discord_user_id: params[:discord_user_id])
      raise ActionController::RoutingError, "Not Found" unless avatar_size.between?(1, 512)
      target = avatar_target(identity)
      expires_in 1.hour, public: true
      redirect_to target, allow_other_host: true
    end

    private

    def avatar_target(identity)
      return Discourse.store.url_for(identity.avatar_upload) if identity.avatar_upload
      return identity.avatar_url if Discord::AvatarUrl.valid?(identity.avatar_url)
      if SiteSetting.discord_chat_bridge_avatar_fallback_url.present?
        return SiteSetting.discord_chat_bridge_avatar_fallback_url
      end

      actor = User.find(BRIDGE_USER_ID)
      URI.join(Discourse.base_url, actor.avatar_template.gsub("{size}", avatar_size.to_s)).to_s
    end

    def avatar_size
      @avatar_size ||= params[:size].to_i
    end
  end
end
