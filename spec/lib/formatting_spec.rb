# frozen_string_literal: true

RSpec.describe DiscordChatBridge::Formatting do
  describe ".discord_to_discourse" do
    it "neutralizes user, group, all, and here mentions" do
      result = described_class.discord_to_discourse("@admin @all @here <@123> <@&456>")

      expect(result).not_to include("@admin", "@all", "@here")
      expect(result).to include("＠admin", "＠user-123", "＠role-456")
    end

    it "converts Discord spoilers without disturbing markdown" do
      expect(described_class.discord_to_discourse("**bold** ||secret||")).to eq(
        "**bold** [spoiler]secret[/spoiler]",
      )
    end
  end

  describe "Discord length handling" do
    it "counts and truncates by UTF-16 code units" do
      expect(described_class.discord_length("a😀")).to eq(3)
      expect(described_class.truncate_for_discord("😀😀", 3)).to eq("😀")
    end
  end

  describe ".escape_discord_link_text" do
    it "escapes names that could change a reply link" do
      expect(described_class.escape_discord_link_text("[click](https://evil.test) ")).to eq(
        "\\[click\\]\\(https://evil.test\\)",
      )
    end
  end

  describe ".digest" do
    it "is stable when nested hash insertion order changes" do
      first = { outer: { "b" => 2, "a" => 1 } }
      second = { "outer" => { "a" => 1, "b" => 2 } }

      expect(described_class.digest(first)).to eq(described_class.digest(second))
    end
  end
end
