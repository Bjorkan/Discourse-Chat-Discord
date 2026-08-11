# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Discord::Client do
  FakeResponse =
    Data.define(:code, :body, :headers) do
      def [](name)
        headers[name]
      end
    end

  subject(:client) { described_class.new(token: "bot-token", rate_limiter:) }

  let(:rate_limiter) { stub }

  before do
    rate_limiter.stubs(:before_request)
    rate_limiter.stubs(:update)
  end

  it "retries a 429 using Discord's retry-after value" do
    limited = FakeResponse.new(code: "429", body: '{"retry_after":0,"global":false}', headers: {})
    success = FakeResponse.new(code: "200", body: '{"id":"123"}', headers: {})
    rate_limiter.expects(:rate_limited!).returns(0)
    client.stubs(:perform).returns(limited, success)

    expect(client.current_user["id"]).to eq("123")
  end

  it "classifies Discord 500 responses as retryable" do
    response = FakeResponse.new(code: "500", body: "{}", headers: {})
    client.stubs(:perform).returns(response)

    expect { client.current_user }.to raise_error(DiscordChatBridge::RetryableError)
  end

  it "classifies a webhook read timeout as an ambiguous delivery" do
    client.stubs(:perform).raises(Net::ReadTimeout)

    expect do
      client.execute_webhook(webhook_id: "123", token: "token", payload: { content: "hello" })
    end.to raise_error(DiscordChatBridge::AmbiguousDeliveryError)
  end

  it "classifies webhook write timeouts and server errors as ambiguous" do
    client.stubs(:perform).raises(Net::WriteTimeout)
    expect do
      client.execute_webhook(webhook_id: "123", token: "token", payload: { content: "hello" })
    end.to raise_error(DiscordChatBridge::AmbiguousDeliveryError)

    response = FakeResponse.new(code: "500", body: "{}", headers: {})
    client.stubs(:perform).returns(response)
    expect do
      client.execute_webhook(webhook_id: "123", token: "token", payload: { content: "hello" })
    end.to raise_error(DiscordChatBridge::AmbiguousDeliveryError)
  end

  it "treats an already-deleted webhook message as success" do
    response = FakeResponse.new(code: "404", body: "{}", headers: {})
    client.stubs(:perform).returns(response)

    expect(
      client.delete_webhook_message(webhook_id: "123", token: "token", message_id: "456"),
    ).to be_nil
  end

  it "rejects zero and oversized snowflakes before making a request" do
    client.expects(:perform).never

    expect { client.channel("0") }.to raise_error(ArgumentError, "invalid Discord snowflake")
    expect { client.channel("1" * 21) }.to raise_error(ArgumentError, "invalid Discord snowflake")
  end
end
