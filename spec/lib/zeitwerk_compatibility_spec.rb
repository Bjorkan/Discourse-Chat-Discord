# frozen_string_literal: true

RSpec.describe DiscordChatBridge do
  it "defines the constant implied by every library file path" do
    library_root = Pathname.new(File.expand_path("../../lib", __dir__))
    failures =
      library_root
        .glob("discord_chat_bridge/**/*.rb")
        .filter_map do |path|
          constant_names =
            path.relative_path_from(library_root).sub_ext("").each_filename.map(&:camelize)

          constant_names.reduce(Object) { |namespace, name| namespace.const_get(name, false) }
          nil
        rescue NameError => error
          "#{path.relative_path_from(library_root)}: #{error.message.lines.first.strip}"
        end

    expect(failures).to be_empty, failures.join("\n")
  end
end
