# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Health do
  before do
    Discourse.redis.del(
      described_class::KEY,
      described_class::SESSION_KEY,
      described_class::STANDBY_KEY,
    )
  end

  after do
    Discourse.redis.del(
      described_class::KEY,
      described_class::SESSION_KEY,
      described_class::STANDBY_KEY,
    )
  end

  it "does not let a standby process refresh the active Gateway health" do
    described_class.update_gateway(connected: true, last_ready_at: Time.zone.now.iso8601)
    active_health = Discourse.redis.get(described_class::KEY)

    expect(Discourse.redis.without_namespace.get(described_class::KEY)).to be_nil

    described_class.record_standby!

    expect(Discourse.redis.get(described_class::KEY)).to eq(active_health)
    expect(described_class.gateway).to include("connected" => true, "standby" => false)

    Discourse.redis.del(described_class::KEY)

    expect(described_class.gateway).to include("connected" => false, "standby" => true)
  end

  it "keeps an active resumable session alive" do
    described_class.save_session("session_id" => "session", "sequence" => 42)
    Discourse.redis.expire(described_class::SESSION_KEY, 1)

    described_class.refresh_session

    expect(Discourse.redis.ttl(described_class::SESSION_KEY)).to be > 3500
    expect(described_class.session).to eq("session_id" => "session", "sequence" => 42)
  end
end
