import { module, test } from "qunit";
import {
  initializeAdminNavigation,
  registerAdminNavigation,
} from "discourse/plugins/discourse-discord-chat-bridge/discourse/initializers/discord-chat-bridge-admin-nav";

module("Discord Chat Bridge | admin navigation", function () {
  test("registers only when the admin plugin API is available", function (assert) {
    let icon;
    let navigation;
    const api = {
      setAdminPluginIcon(pluginId, value) {
        icon = { pluginId, value };
      },
      addAdminPluginConfigurationNav(pluginId, items) {
        navigation = { pluginId, items };
      },
    };

    assert.true(registerAdminNavigation(api));
    assert.deepEqual(icon, {
      pluginId: "discourse-discord-chat-bridge",
      value: "discord",
    });
    assert.strictEqual(
      navigation.items[0].route,
      "adminPlugins.show.discourse-discord-chat-bridge-control"
    );
    assert.false(registerAdminNavigation({}));
  });

  test("never throws during optional admin navigation setup", function (assert) {
    const adminContainer = {
      lookup() {
        return { admin: true };
      },
    };
    const userContainer = {
      lookup() {
        return { admin: false };
      },
    };

    assert.false(initializeAdminNavigation(userContainer));
    assert.false(
      initializeAdminNavigation(adminContainer, () => {
        throw new Error("admin plugin API unavailable");
      })
    );
  });
});
