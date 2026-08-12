# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Outbound::UpdateMessage do
  fab!(:user)
  fab!(:chat_channel)
  fab!(:message) { Fabricate(:chat_message, chat_channel:, user:, message: "Before") }
  let(:client) { mock }
  let!(:channel_mapping) do
    mapping =
      Fabricate.build(
        :discord_chat_bridge_channel_mapping,
        chat_channel:,
        direction: "bidirectional",
        discord_webhook_id: "500",
      )
    mapping.webhook_token = "webhook-token"
    mapping.save!
    mapping
  end
  let!(:message_mapping) do
    Fabricate(
      :discord_chat_bridge_message_mapping,
      channel_mapping:,
      chat_message: message,
      discord_message_id: "600",
      origin: "discourse",
      delivery_status: "delivered",
      payload_digest: "old",
    )
  end

  before { SiteSetting.discord_chat_bridge_enabled = true }

  it "edits the existing webhook message with safe mentions" do
    message.update!(message: "After @someone")
    client
      .expects(:edit_webhook_message)
      .with do |args|
        args[:message_id] == "600" && args[:payload][:content] == "After @someone" &&
          args[:payload][:allowed_mentions] == { parse: [] }
      end
      .returns({ "id" => "600", "attachments" => [] })

    DiscordChatBridge::Outbound::UpdateMessage.new(message.id, client:).call
    expect(message_mapping.reload.discourse_last_edited_at).to be_present
  end

  it "deletes the existing webhook message and treats a missing message as success in the client contract" do
    client
      .expects(:delete_webhook_message)
      .with(message_id: "600", webhook_id: "500", token: "webhook-token")
      .returns(nil)

    DiscordChatBridge::Outbound::DeleteMessage.new(message.id, client:).call
    expect(message_mapping.reload.deleted_on_discord_at).to be_present
  end

  it "never exports local moderator edits of Discord-origin messages" do
    message_mapping.update!(origin: "discord")
    client.expects(:edit_webhook_message).never

    DiscordChatBridge::Outbound::UpdateMessage.new(message.id, client:).call
  end

  it "retries a failed create when the Discourse message is edited" do
    message_mapping.update!(
      discord_message_id: "pending:delivery-nonce",
      delivery_status: "failed",
      last_error: "Discord returned HTTP 404",
    )
    client
      .expects(:execute_webhook)
      .with do |args|
        args[:webhook_id] == channel_mapping.discord_webhook_id &&
          args.dig(:payload, :content) == message.message
      end
      .returns({ "id" => "601", "attachments" => [] })

    DiscordChatBridge::Outbound::UpdateMessage.new(message.id, client:).call

    expect(message_mapping.reload).to have_attributes(
      discord_message_id: "601",
      delivery_status: "delivered",
      last_error: nil,
    )
  end
end
