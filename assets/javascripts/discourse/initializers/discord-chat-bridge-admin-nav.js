import { withPluginApi } from "discourse/lib/plugin-api";

// Discourse identifies an installed plugin by its directory name on the admin show route. The
// canonical GitHub checkout keeps the repository's capitalization, while existing installations
// may use the metadata name as their directory.
const ADMIN_PLUGIN_IDS = [
  "Discourse-Chat-Discord",
  "discourse-discord-chat-bridge",
];

export function registerAdminNavigation(api) {
  if (
    typeof api.setAdminPluginIcon !== "function" ||
    typeof api.addAdminPluginConfigurationNav !== "function"
  ) {
    return false;
  }

  let registered = false;
  for (const pluginId of ADMIN_PLUGIN_IDS) {
    try {
      api.setAdminPluginIcon(pluginId, "discord");
      api.addAdminPluginConfigurationNav(pluginId, [
        {
          label: "discord_chat_bridge.admin.overview",
          route: "adminPlugins.show.discourse-discord-chat-bridge-control",
          description: "discord_chat_bridge.admin.description",
        },
      ]);
      registered = true;
    } catch {
      // A failed optional admin enhancement must never prevent the application from booting.
    }
  }
  return registered;
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
