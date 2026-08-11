# frozen_string_literal: true

DiscordChatBridge::Engine.routes.draw do
  constraints StaffConstraint.new do
    get "admin" => "admin#index"
    put "admin/credentials" => "admin#credentials"
    post "admin/test" => "admin#test"
    post "admin/reconnect" => "admin#reconnect"
    post "admin/mappings" => "admin#create_mapping"
    put "admin/mappings/:id" => "admin#update_mapping"
    delete "admin/mappings/:id" => "admin#destroy_mapping"
  end

  get "avatar/:discord_user_id/:size.png" => "avatars#show",
      :constraints => {
        discord_user_id: /\d+/,
        size: /\d+/,
      }
end
