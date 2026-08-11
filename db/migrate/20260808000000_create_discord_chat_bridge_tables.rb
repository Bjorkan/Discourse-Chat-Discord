# frozen_string_literal: true

class CreateDiscordChatBridgeTables < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_chat_bridge_channel_mappings do |t|
      t.string :discord_guild_id, null: false
      t.string :discord_channel_id, null: false
      t.bigint :chat_channel_id, null: false
      t.string :direction, null: false, default: "bidirectional"
      t.boolean :enabled, null: false, default: true
      t.string :discord_webhook_id
      t.text :encrypted_discord_webhook_token
      t.datetime :activated_at, null: false
      t.datetime :archived_at
      t.datetime :last_success_at
      t.datetime :last_error_at
      t.string :last_error_code
      t.text :last_error_message
      t.timestamps
    end

    add_foreign_key :discord_chat_bridge_channel_mappings,
                    :chat_channels,
                    column: :chat_channel_id,
                    on_delete: :restrict
    add_index :discord_chat_bridge_channel_mappings,
              :discord_channel_id,
              unique: true,
              where: "enabled",
              name: "dcb_enabled_discord_channel_unique"
    add_index :discord_chat_bridge_channel_mappings,
              :chat_channel_id,
              unique: true,
              where: "enabled",
              name: "dcb_enabled_chat_channel_unique"
    add_index :discord_chat_bridge_channel_mappings, :discord_webhook_id

    create_table :discord_chat_bridge_identities do |t|
      t.string :discord_user_id, null: false
      t.string :discord_username, null: false
      t.string :discord_global_name
      t.string :display_name, null: false
      t.string :avatar_hash
      t.text :avatar_url
      t.bigint :avatar_upload_id
      t.datetime :last_synced_at, null: false
      t.timestamps
    end

    add_index :discord_chat_bridge_identities, :discord_user_id, unique: true
    add_foreign_key :discord_chat_bridge_identities,
                    :uploads,
                    column: :avatar_upload_id,
                    on_delete: :nullify

    create_table :discord_chat_bridge_message_mappings do |t|
      t.bigint :channel_mapping_id, null: false
      t.bigint :chat_message_id
      t.string :discord_message_id, null: false
      t.string :origin, null: false
      t.bigint :discord_identity_id
      t.string :discord_channel_id, null: false
      t.bigint :discourse_chat_channel_id, null: false
      t.string :author_display_name
      t.string :author_username
      t.string :author_avatar_url
      t.datetime :discord_last_edited_at
      t.datetime :discourse_last_edited_at
      t.datetime :deleted_on_discord_at
      t.datetime :deleted_on_discourse_at
      t.string :delivery_status, null: false, default: "delivered"
      t.string :payload_digest
      t.string :delivery_nonce
      t.jsonb :discord_attachments, null: false, default: []
      t.jsonb :discourse_upload_ids, null: false, default: []
      t.text :last_error
      t.timestamps
    end

    add_foreign_key :discord_chat_bridge_message_mappings,
                    :discord_chat_bridge_channel_mappings,
                    column: :channel_mapping_id,
                    on_delete: :restrict
    add_foreign_key :discord_chat_bridge_message_mappings,
                    :chat_messages,
                    column: :chat_message_id,
                    on_delete: :nullify
    add_foreign_key :discord_chat_bridge_message_mappings,
                    :discord_chat_bridge_identities,
                    column: :discord_identity_id,
                    on_delete: :restrict
    add_index :discord_chat_bridge_message_mappings,
              :chat_message_id,
              unique: true,
              where: "chat_message_id IS NOT NULL",
              name: "dcb_chat_message_unique"
    add_index :discord_chat_bridge_message_mappings,
              %i[discord_channel_id discord_message_id],
              unique: true,
              name: "dcb_discord_message_unique"
    add_index :discord_chat_bridge_message_mappings, :discord_identity_id
    add_index :discord_chat_bridge_message_mappings, :delivery_status

    create_table :discord_chat_bridge_event_states do |t|
      t.string :discord_channel_id, null: false
      t.string :discord_message_id, null: false
      t.bigint :gateway_sequence
      t.string :gateway_session_id
      t.string :latest_event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :discord_deleted_at
      t.datetime :processed_at
      t.integer :processing_attempts, null: false, default: 0
      t.text :last_error
      t.timestamps
    end

    add_index :discord_chat_bridge_event_states,
              %i[discord_channel_id discord_message_id],
              unique: true,
              name: "dcb_event_message_unique"
    add_index :discord_chat_bridge_event_states, :updated_at
  end
end
