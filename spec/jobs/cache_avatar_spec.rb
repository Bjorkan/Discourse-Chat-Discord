# frozen_string_literal: true

RSpec.describe Jobs::DiscordChatBridge::CacheAvatar do
  fab!(:identity, :discord_chat_bridge_identity)
  fab!(:previous_upload, :upload)
  fab!(:current_upload, :upload)

  it "removes an unreferenced avatar upload after replacement" do
    identity.update!(avatar_upload: current_upload)

    described_class.new.send(:remove_previous_upload, previous_upload.id, identity)

    expect(Upload.exists?(previous_upload.id)).to eq(false)
    expect(identity.reload.avatar_upload).to eq(current_upload)
  end
end
