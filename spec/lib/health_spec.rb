# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Health do
  before { Discourse.redis.del(described_class::KEY, described_class::STANDBY_KEY) }

  after { Discourse.redis.del(described_class::KEY, described_class::STANDBY_KEY) }

  it "does not let a standby process refresh the active Gateway health" do
    described_class.update_gateway(connected: true, last_ready_at: Time.zone.now.iso8601)
    active_health = Discourse.redis.get(described_class::KEY)

    described_class.record_standby!

    expect(Discourse.redis.get(described_class::KEY)).to eq(active_health)
    expect(described_class.gateway).to include("connected" => true, "standby" => false)

    Discourse.redis.del(described_class::KEY)

    expect(described_class.gateway).to include("connected" => false, "standby" => true)
  end
end
