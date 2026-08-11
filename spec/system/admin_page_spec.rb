# frozen_string_literal: true

RSpec.describe "Discord Chat Bridge | admin page" do
  fab!(:admin)

  before do
    SiteSetting.chat_enabled = true
    sign_in(admin)
  end

  it "loads the plugin configuration without a client error" do
    visit "/admin/plugins/discourse-discord-chat-bridge/bridge"

    expect(page).to have_css(".discord-chat-bridge-admin")
    expect(page).to have_content("Discord Chat Bridge")
  end
end
