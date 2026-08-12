# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Discord::Gateway do
  subject(:gateway) { described_class.new(client:) }

  let(:client) { stub(gateway_bot: { "url" => "wss://gateway.discord.gg" }) }

  it "identifies with only GUILDS, GUILD_MESSAGES, and MESSAGE_CONTENT intents" do
    websocket = mock
    gateway.instance_variable_set(:@websocket, websocket)
    websocket
      .expects(:send)
      .with do |json|
        payload = JSON.parse(json)
        payload["op"] == 2 && payload.dig("d", "intents") == 33_281
      end

    DiscordChatBridge::Credentials.stubs(:bot_token).returns("filtered-token")
    gateway.send(:identify)
  end

  it "resumes with the persisted session and sequence" do
    websocket = mock
    gateway.instance_variable_set(:@websocket, websocket)
    gateway.instance_variable_set(
      :@session,
      {
        "session_id" => "session",
        "sequence" => 42,
        "resume_gateway_url" => "wss://resume.discord.gg",
      },
    )
    websocket
      .expects(:send)
      .with do |json|
        payload = JSON.parse(json)
        payload["op"] == 6 && payload.dig("d", "session_id") == "session" &&
          payload.dig("d", "seq") == 42
      end

    DiscordChatBridge::Credentials.stubs(:bot_token).returns("filtered-token")
    gateway.send(:resume)
  end

  it "uses the resume URL for a resumable session" do
    gateway.instance_variable_set(
      :@session,
      {
        "session_id" => "session",
        "sequence" => 42,
        "resume_gateway_url" => "wss://resume.discord.gg",
      },
    )

    expect(gateway.send(:gateway_url)).to eq("wss://resume.discord.gg?v=10&encoding=json")
  end

  it "rejects unsafe Gateway and resume URLs" do
    gateway.instance_variable_set(
      :@session,
      { "session_id" => "session", "sequence" => 42, "resume_gateway_url" => "wss://example.test" },
    )

    expect { gateway.send(:gateway_url) }.to raise_error(
      DiscordChatBridge::PermanentError,
      "Discord returned an invalid Gateway URL",
    )
  end

  it "turns callback exceptions into a reconnect instead of stranding the Gateway" do
    websocket = mock
    websocket.expects(:close)
    gateway.instance_variable_set(:@websocket, websocket)
    gateway.instance_variable_set(:@mutex, Mutex.new)
    gateway.instance_variable_set(:@condition, ConditionVariable.new)
    gateway.instance_variable_set(:@closed, false)

    gateway.send(:guard_callback, "message") { raise "Redis unavailable" }

    expect(gateway.instance_variable_get(:@closed)).to eq(true)
    expect(gateway.instance_variable_get(:@fatal_error)).to be_a(DiscordChatBridge::RetryableError)
  end

  it "reports connected only after Discord sends READY" do
    callbacks = {}
    websocket = Object.new
    websocket.define_singleton_method(:on) { |event, &callback| callbacks[event] = callback }
    DiscordChatBridge::Health.update_gateway(
      connected: false,
      connecting: true,
      websocket_open: false,
    )
    gateway.send(:register_callbacks, websocket)

    callbacks.fetch(:open).call

    expect(DiscordChatBridge::Health.gateway).to include(
      "connected" => false,
      "connecting" => true,
      "websocket_open" => true,
    )

    gateway.send(
      :handle_dispatch,
      {
        "t" => "READY",
        "d" => {
          "session_id" => "session",
          "resume_gateway_url" => "wss://resume.discord.gg",
          "user" => {
            "id" => "bot-user",
          },
        },
      },
    )

    expect(DiscordChatBridge::Health.gateway).to include(
      "connected" => true,
      "connecting" => false,
      "websocket_open" => true,
      "bot_user_id" => "bot-user",
    )
  end

  it "does not let a health write failure mask shutdown" do
    DiscordChatBridge::Health.expects(:update_gateway).raises("Redis unavailable")

    expect { gateway.send(:safely_mark_disconnected) }.not_to raise_error
  end
end
