# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Discord::LeaderLease do
  after { described_class.new.tap(&:release) }

  it "allows only one active Gateway owner" do
    first = described_class.new
    second = described_class.new

    expect(first.acquire).to eq(true)
    expect(second.acquire).to eq(false)
  ensure
    first&.release
    second&.release
  end
end
