# frozen_string_literal: true

module DiscordChatBridge
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscordChatBridge

    config.autoload_paths << root.join("lib")
    config.eager_load_paths << root.join("lib")

    jobs_glob = root.join("app/jobs/**/*.rb")
    config.to_prepare { Dir[jobs_glob].each { |file| require_dependency file } }
  end
end
