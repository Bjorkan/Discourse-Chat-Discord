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
end
