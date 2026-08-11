# frozen_string_literal: true

RSpec.describe "Discord Chat Bridge | site boot" do
  it "does not prevent the anonymous application from booting" do
    visit "/"

    expect(page).to have_css(".d-header")
    expect(page).to have_no_css("#d-splash")
  end
end
