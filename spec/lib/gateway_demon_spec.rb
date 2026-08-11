# frozen_string_literal: true

RSpec.describe DiscordChatBridge::GatewayDemon do
  subject(:demon) { described_class.new(0) }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.discord_chat_bridge_enabled = true
    SiteSetting.discord_chat_bridge_gateway_autostart = true
    DiscordChatBridge::Credentials.stubs(:bot_token?).returns(true)
    DiscordChatBridge::DiscourseIntegration.stubs(:compatible?).returns(true)
  end

  it "runs only when Chat and an inbound mapping are available" do
    Fabricate(:discord_chat_bridge_channel_mapping, direction: "discord_to_discourse")

    expect(demon.send(:runnable?)).to eq(true)
  end

  it "stays paused when Discourse Chat is disabled" do
    Fabricate(:discord_chat_bridge_channel_mapping, direction: "discord_to_discourse")
    SiteSetting.chat_enabled = false

    expect(demon.send(:runnable?)).to eq(false)
  end

  it "caches the mapping lookup used by the one-second watchdog" do
    relation = mock
    DiscordChatBridge::ChannelMapping.stubs(:active).once.returns(relation)
    relation.expects(:any?).once.returns(true)

    2.times { expect(demon.send(:runnable?)).to eq(true) }
  end
end
