import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-discord-chat-bridge";

export default {
  name: "discord-chat-bridge-admin-nav",

  initialize(container) {
    if (!container.lookup("service:current-user")?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "discord");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "discord_chat_bridge.admin.overview",
          route: "adminPlugins.show.discourse-discord-chat-bridge-control",
          description: "discord_chat_bridge.admin.description",
        },
      ]);
    });
  },
};
