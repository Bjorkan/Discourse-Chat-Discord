# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Outbound::CreateMessage do
  fab!(:user)
  fab!(:chat_channel)
  fab!(:message) { Fabricate(:chat_message, chat_channel:, user:, message: "Hello @everyone") }
  let(:client) { mock }
  let!(:mapping) do
    record =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        chat_channel:,
        direction: "bidirectional",
        discord_channel_id: "200",
        discord_guild_id: "400",
        discord_webhook_id: "500",
      )
    record.webhook_token = "webhook-secret"
    record.save!
    record
  end

  before { SiteSetting.discord_chat_bridge_enabled = true }

  it "executes one identity-overridden webhook with no allowed pings and stores its ID" do
    client
      .expects(:execute_webhook)
      .with do |args|
        args[:webhook_id] == "500" && args[:token] == "webhook-secret" &&
          args[:payload][:username] == (user.name.presence || user.username) &&
          args[:payload][:avatar_url].present? &&
          args[:payload][:allowed_mentions] == { parse: [] } &&
          args[:payload][:content] == "Hello @everyone"
      end
      .returns({ "id" => "600", "attachments" => [] })

    described_class.new(message.id, client:).call
    stored = DiscordChatBridge::MessageMapping.last
    expect(stored.discord_message_id).to eq("600")
    expect(stored.origin).to eq("discourse")
    expect(stored.delivery_status).to eq("delivered")
  end

  it "does not send a delivered message twice" do
    client.expects(:execute_webhook).once.returns({ "id" => "600", "attachments" => [] })
    2.times { described_class.new(message.id, client:).call }
  end

  it "quarantines ambiguous network success instead of creating a duplicate on retry" do
    client
      .expects(:execute_webhook)
      .once
      .raises(DiscordChatBridge::AmbiguousDeliveryError, "timeout")
    described_class.new(message.id, client:).call
    described_class.new(message.id, client:).call

    expect(DiscordChatBridge::MessageMapping.last.delivery_status).to eq("ambiguous")
  end

  it "skips Discord-origin messages and the technical actor" do
    ensure_bridge_actor
    external =
      Fabricate(:chat_message, chat_channel:, user: User.find(DiscordChatBridge::BRIDGE_USER_ID))
    client.expects(:execute_webhook).never

    described_class.new(external.id, client:).call
  end

  it "does not resurrect a Chat message deleted before its create job runs" do
    message.update_column(:deleted_at, Time.zone.now)
    client.expects(:execute_webhook).never

    described_class.new(message.id, client:).call
  end

  it "adds compact linked reply context without undocumented webhook reply fields" do
    parent = Fabricate(:chat_message, chat_channel:, user:, message: "Original text")
    parent_mapping =
      Fabricate(
        :discord_chat_bridge_message_mapping,
        channel_mapping: mapping,
        chat_message: parent,
        discord_message_id: "601",
        discord_channel_id: "200",
        discourse_chat_channel_id: chat_channel.id,
        origin: "discourse",
      )
    reply = Fabricate(:chat_message, chat_channel:, user:, in_reply_to: parent, message: "Reply")

    client
      .expects(:execute_webhook)
      .with do |args|
        content = args[:payload][:content]
        content.include?(
          "https://discord.com/channels/400/200/#{parent_mapping.discord_message_id}",
        ) && !args[:payload].key?(:message_reference)
      end
      .returns({ "id" => "602", "attachments" => [] })

    described_class.new(reply.id, client:).call
  end
end
