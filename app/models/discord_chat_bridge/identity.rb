# frozen_string_literal: true

module DiscordChatBridge
  class Identity < ActiveRecord::Base
    self.table_name = "discord_chat_bridge_identities"

    belongs_to :avatar_upload, class_name: "Upload", optional: true
    has_many :message_mappings, class_name: "DiscordChatBridge::MessageMapping", dependent: :nullify

    validates :discord_user_id, :discord_username, :display_name, :last_synced_at, presence: true
    validates :discord_user_id, format: { with: ChannelMapping::SNOWFLAKE_FORMAT }
    validates :discord_user_id, uniqueness: true

    def browser_user_id
      -2_000_000_000 - id
    end

    def avatar_template
      "/discord-chat-bridge/avatar/#{discord_user_id}/{size}.png"
    end
  end
end

# == Schema Information
#
# Table name: discord_chat_bridge_identities
#
#  id                  :bigint           not null, primary key
#  avatar_hash         :string
#  avatar_url          :text
#  discord_global_name :string
#  discord_username    :string           not null
#  display_name        :string           not null
#  last_synced_at      :datetime         not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  avatar_upload_id    :bigint
#  discord_user_id     :string           not null
#
# Indexes
#
#  index_discord_chat_bridge_identities_on_discord_user_id  (discord_user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (avatar_upload_id => uploads.id) ON DELETE => nullify
#
