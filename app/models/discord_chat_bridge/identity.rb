# frozen_string_literal: true

module DiscordChatBridge
  class Identity < ActiveRecord::Base
    self.table_name = "discord_chat_bridge_identities"

    belongs_to :avatar_upload, class_name: "Upload", optional: true
    has_many :message_mappings, class_name: "DiscordChatBridge::MessageMapping", dependent: :nullify

    validates :discord_user_id, :discord_username, :display_name, :last_synced_at, presence: true
    validates :discord_user_id, uniqueness: true

    def browser_user_id
      -2_000_000_000 - id
    end

    def avatar_template
      "/discord-chat-bridge/avatar/#{discord_user_id}/{size}.png"
    end
  end
end
