# frozen_string_literal: true

module DiscordChatBridge
  # Base class for failures raised by the bridge.
  #
  # This hierarchy intentionally lives in error.rb. Zeitwerk requires the file
  # name to match at least one constant it defines, and therefore expects
  # DiscordChatBridge::Error from this path during production eager loading.
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
