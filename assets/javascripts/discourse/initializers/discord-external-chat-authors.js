import { schedule } from "@ember/runloop";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import ChatMessage from "discourse/plugins/chat/discourse/models/chat-message" with {
  discourseImport: "optional",
};

function retainExternalAuthorMetadata() {
  if (!ChatMessage || ChatMessage.discordChatBridgePatched) {
    return;
  }

  const originalCreate = ChatMessage.create.bind(ChatMessage);
  ChatMessage.create = (channel, args = {}) => {
    const message = originalCreate(channel, args);
    message.externalAuthor = args.external_author;
    return message;
  };
  ChatMessage.discordChatBridgePatched = true;
}

export function decorateExternalAuthor(element) {
  schedule("afterRender", () => {
    const row = element.closest(".chat-message");
    row?.querySelectorAll("a[data-user-card]").forEach((link) => {
      const avatarUrl = link.querySelector("img")?.getAttribute("src");
      if (!avatarUrl?.includes("/discord-chat-bridge/avatar/")) {
        return;
      }

      const avatar = document.createElement("span");
      avatar.className = link.className;
      avatar.append(...link.childNodes);
      link.replaceWith(avatar);
    });

    const author = row?.querySelector(".group--discord-external");
    if (!author || author.dataset.discordExternalDecorated) {
      return;
    }

    author.dataset.discordExternalDecorated = "true";
    author.removeAttribute("role");
    author.removeAttribute("data-user-card");
    author.classList.remove("clickable");
    author.classList.add("discord-chat-bridge-author");

    const badge = document.createElement("span");
    badge.className = "discord-chat-bridge-source";
    badge.textContent = i18n("discord_chat_bridge.source_badge");
    author.insertAdjacentElement("afterend", badge);
  });
}

export function registerExternalAuthorDecorator(api) {
  if (typeof api.decorateChatMessage !== "function") {
    return false;
  }

  api.decorateChatMessage(decorateExternalAuthor);
  return true;
}

export default {
  name: "discord-external-chat-authors",
  after: "chat-plugin-api",

  initialize() {
    retainExternalAuthorMetadata();
    withPluginApi(registerExternalAuthorDecorator);
  },
};
