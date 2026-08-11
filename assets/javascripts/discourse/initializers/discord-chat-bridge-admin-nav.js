import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-discord-chat-bridge";

export function registerAdminNavigation(api) {
  if (
    typeof api.setAdminPluginIcon !== "function" ||
    typeof api.addAdminPluginConfigurationNav !== "function"
  ) {
    return false;
  }

  try {
    api.setAdminPluginIcon(PLUGIN_ID, "discord");
    api.addAdminPluginConfigurationNav(PLUGIN_ID, [
      {
        label: "discord_chat_bridge.admin.overview",
        route: "adminPlugins.show.discourse-discord-chat-bridge-control",
        description: "discord_chat_bridge.admin.description",
      },
    ]);
    return true;
  } catch {
    return false;
  }
}

export function initializeAdminNavigation(container, withApi = withPluginApi) {
  if (!container.lookup("service:current-user")?.admin) {
    return false;
  }

  try {
    return withApi(registerAdminNavigation) ?? true;
  } catch {
    return false;
  }
}

export default {
  name: "discord-chat-bridge-admin-nav",

  initialize(container) {
    initializeAdminNavigation(container);
  },
};
