import { module, test } from "qunit";
import {
  initializeAdminNavigation,
  registerAdminNavigation,
} from "discourse/plugins/discourse-discord-chat-bridge/discourse/initializers/discord-chat-bridge-admin-nav";

module("Discord Chat Bridge | admin navigation", function () {
  test("registers only when the admin plugin API is available", function (assert) {
    const icons = [];
    const navigations = [];
    const api = {
      setAdminPluginIcon(pluginId, value) {
        icons.push({ pluginId, value });
      },
      addAdminPluginConfigurationNav(pluginId, items) {
        navigations.push({ pluginId, items });
      },
    };

    assert.true(registerAdminNavigation(api));
    assert.deepEqual(icons[0], {
      pluginId: "Discourse-Chat-Discord",
      value: "discord",
    });
    assert.strictEqual(
      navigations[0].items[0].route,
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
