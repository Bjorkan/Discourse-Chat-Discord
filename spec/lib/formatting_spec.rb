# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Formatting do
  describe ".discord_to_discourse" do
    it "neutralizes user, group, all, and here mentions" do
      result = described_class.discord_to_discourse("@admin @all @here <@123> <@&456>")

      expect(result).not_to include("@admin", "@all", "@here")
      expect(result).to include("\uFF20admin", "\uFF20user-123", "\uFF20role-456")
    end

    it "converts Discord spoilers without disturbing markdown" do
      expect(described_class.discord_to_discourse("**bold** ||secret||")).to eq(
        "**bold** [spoiler]secret[/spoiler]",
      )
    end
  end
end
