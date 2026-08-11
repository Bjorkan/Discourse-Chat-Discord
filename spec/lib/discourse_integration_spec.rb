# frozen_string_literal: true

RSpec.describe DiscordChatBridge::DiscourseIntegration do
  it "finds every required integration point in the supported Discourse version" do
    expect(described_class.missing_constants).to be_empty
  end

  it "installs every serializer patch idempotently" do
    2.times { expect(described_class.install_patches).to be_empty }

    described_class::PATCHES.each do |target_name, extension_name|
      expect(target_name.constantize.ancestors).to include(extension_name.constantize)
    end
  end

  it "reports a missing integration point instead of raising during boot" do
    logger = mock
    logger.expects(:error).with(includes("Missing::ChatSerializer"))

    expect(
      described_class.install_patches(
        patches: {
          "Missing::ChatSerializer" => "DiscordChatBridge::MessageSerializerExtension",
        },
        logger:,
      ),
    ).to eq(["Missing::ChatSerializer"])
  end
end
