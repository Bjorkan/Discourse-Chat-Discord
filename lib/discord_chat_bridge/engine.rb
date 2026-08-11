# frozen_string_literal: true

module DiscordChatBridge
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscordChatBridge

    config.autoload_paths << File.join(config.root, "lib")
    scheduled_job_dir = File.join(config.root, "app/jobs/scheduled")
    config.to_prepare do
      Rails.autoloaders.main.eager_load_dir(scheduled_job_dir) if Dir.exist?(scheduled_job_dir)
    end
  end
end
