# frozen_string_literal: true

module DiscordChatBridge
  module MessageSerializerExtension
    include SerializerSupport

    def self.prepended(base)
      base.attributes :external_author
    end

    def user
      external_user_json || super
    end

    def include_external_author?
      external_author.present?
    end
  end
end
