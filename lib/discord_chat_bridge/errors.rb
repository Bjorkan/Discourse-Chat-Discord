# frozen_string_literal: true

module DiscordChatBridge
  class Error < StandardError
  end
  class RetryableError < Error
    attr_reader :retry_after

    def initialize(message, retry_after: nil)
      @retry_after = retry_after
      super(message)
    end
  end
  class PermanentError < Error
  end
  class AmbiguousDeliveryError < Error
  end
end
