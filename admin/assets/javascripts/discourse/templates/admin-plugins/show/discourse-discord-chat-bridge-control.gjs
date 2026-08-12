import DBreadcrumbsItem from "discourse/ui-kit/d-breadcrumbs-item";
import { i18n } from "discourse-i18n";
import DiscordChatBridgeAdmin from "discourse/plugins/discourse-discord-chat-bridge/admin/components/discord-chat-bridge-admin";

export default <template>
  <DBreadcrumbsItem
    @path="/admin/plugins/discourse-discord-chat-bridge/bridge"
    @label={{i18n "discord_chat_bridge.admin.title"}}
  />
  <DiscordChatBridgeAdmin @state={{@model}} />
</template>
