export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",

  map() {
    this.route("discourse-discord-chat-bridge-control", { path: "bridge" });
  },
};
