import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class DiscordChatBridgeControlRoute extends DiscourseRoute {
  model() {
    return ajax("/discord-chat-bridge/admin");
  }

  titleToken() {
    return i18n("discord_chat_bridge.admin.title");
  }
}
