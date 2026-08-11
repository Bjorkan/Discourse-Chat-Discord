import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import DToggleSwitch from "discourse/ui-kit/d-toggle-switch";
import { i18n } from "discourse-i18n";

const DIRECTIONS = [
  "bidirectional",
  "discord_to_discourse",
  "discourse_to_discord",
];

export default class DiscordChatBridgeAdmin extends Component {
  @tracked state;
  @tracked loading = false;
  @tracked botToken = "";
  @tracked testResult;
  @tracked guildId = "";
  @tracked discordChannelId = "";
  @tracked chatChannelId = "";
  @tracked direction = "bidirectional";
  @tracked webhookUrl = "";

  directions = DIRECTIONS;

  constructor() {
    super(...arguments);
    this.state = this.args.state;
  }

  get gatewayConnected() {
    return this.state.gateway?.connected;
  }

  get hasMappings() {
    return this.state.mappings?.length > 0;
  }

  @action
  async toggleEnabled() {
    await this.updateCredentials({ enabled: !this.state.enabled });
  }

  @action
  async saveToken() {
    if (!this.botToken.trim()) {
      return;
    }
    await this.updateCredentials({ bot_token: this.botToken });
    this.botToken = "";
  }

  async updateCredentials(data) {
    this.loading = true;
    try {
      this.state = await ajax("/discord-chat-bridge/admin/credentials", {
        type: "PUT",
        data,
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  updateMappings(mappings) {
    this.state = {
      ...this.state,
      mappings,
      summary: {
        ...this.state.summary,
        enabled_mappings: mappings.filter((mapping) => mapping.enabled).length,
        mapping_errors: mappings.filter(
          (mapping) => mapping.enabled && mapping.last_error_at
        ).length,
      },
    };
  }

  @action
  async testConnection() {
    this.loading = true;
    this.testResult = null;
    try {
      const result = await ajax("/discord-chat-bridge/admin/test", {
        type: "POST",
      });
      this.testResult = `${result.bot.username} (${result.bot.id})`;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async reconnect() {
    this.loading = true;
    try {
      await ajax("/discord-chat-bridge/admin/reconnect", { type: "POST" });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  setBotToken(event) {
    this.botToken = event.target.value;
  }

  @action
  setGuildId(event) {
    this.guildId = event.target.value;
  }

  @action
  setDiscordChannelId(event) {
    this.discordChannelId = event.target.value;
  }

  @action
  setChatChannelId(event) {
    this.chatChannelId = event.target.value;
  }

  @action
  setDirection(event) {
    this.direction = event.target.value;
  }

  @action
  setWebhookUrl(event) {
    this.webhookUrl = event.target.value;
  }

  @action
  async testMapping(mapping) {
    this.loading = true;
    try {
      await ajax("/discord-chat-bridge/admin/test", {
        type: "POST",
        data: { mapping_id: mapping.id },
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async createMapping(event) {
    event.preventDefault();
    this.loading = true;
    try {
      const result = await ajax("/discord-chat-bridge/admin/mappings", {
        type: "POST",
        data: {
          discord_guild_id: this.guildId,
          discord_channel_id: this.discordChannelId,
          chat_channel_id: this.chatChannelId,
          direction: this.direction,
          webhook_url: this.webhookUrl,
          enabled: true,
        },
      });
      this.updateMappings([...this.state.mappings, result.mapping]);
      this.guildId = "";
      this.discordChannelId = "";
      this.chatChannelId = "";
      this.webhookUrl = "";
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async disableMapping(mapping) {
    this.loading = true;
    try {
      const result = await ajax(
        `/discord-chat-bridge/admin/mappings/${mapping.id}`,
        { type: "DELETE" }
      );
      this.updateMappings(
        this.state.mappings.map((item) =>
          item.id === mapping.id ? result.mapping : item
        )
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async enableMapping(mapping) {
    this.loading = true;
    try {
      const result = await ajax(
        `/discord-chat-bridge/admin/mappings/${mapping.id}`,
        {
          type: "PUT",
          data: { enabled: true },
        }
      );
      this.updateMappings(
        this.state.mappings.map((item) =>
          item.id === mapping.id ? result.mapping : item
        )
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  <template>
    <section class="admin-detail discord-chat-bridge-admin">
      <DPageSubheader
        @titleLabel={{i18n "discord_chat_bridge.admin.title"}}
        @descriptionLabel={{i18n "discord_chat_bridge.admin.description"}}
      />

      {{#unless this.state.integration.chat_enabled}}
        <div class="alert alert-error" role="alert">
          {{i18n "discord_chat_bridge.admin.chat_disabled_error"}}
        </div>
      {{/unless}}

      {{#unless this.state.integration.compatible}}
        <div class="alert alert-error" role="alert">
          <strong>{{i18n
              "discord_chat_bridge.admin.incompatible_error"
            }}</strong>
          <ul>
            {{#each this.state.integration.missing_constants as |name|}}
              <li><code>{{name}}</code></li>
            {{/each}}
          </ul>
        </div>
      {{/unless}}

      <div class="discord-chat-bridge-status" aria-live="polite">
        <div>
          <span class="discord-chat-bridge-status__label">{{i18n
              "discord_chat_bridge.admin.gateway"
            }}</span>
          <strong
            class={{if this.gatewayConnected "is-healthy" "is-unhealthy"}}
          >
            {{if
              this.gatewayConnected
              (i18n "discord_chat_bridge.admin.connected")
              (i18n "discord_chat_bridge.admin.disconnected")
            }}
          </strong>
        </div>
        <div>
          <span class="discord-chat-bridge-status__label">{{i18n
              "discord_chat_bridge.admin.last_event"
            }}</span>
          <strong>{{or
              this.state.gateway.last_event_at
              (i18n "discord_chat_bridge.admin.never")
            }}</strong>
        </div>
        <div>
          <span class="discord-chat-bridge-status__label">{{i18n
              "discord_chat_bridge.admin.mapping_health"
            }}</span>
          <strong
            class={{if
              this.state.summary.mapping_errors
              "is-unhealthy"
              "is-healthy"
            }}
          >
            {{i18n
              "discord_chat_bridge.admin.mapping_summary"
              enabled=this.state.summary.enabled_mappings
              errors=this.state.summary.mapping_errors
            }}
          </strong>
        </div>
      </div>

      {{#if this.state.gateway.last_error}}
        <div class="alert alert-error" role="alert">
          Gateway:
          {{this.state.gateway.last_error}}
        </div>
      {{/if}}

      <div class="discord-chat-bridge-section">
        <h3>{{i18n "discord_chat_bridge.admin.runtime"}}</h3>
        <div class="discord-chat-bridge-runtime-controls">
          <label class="discord-chat-bridge-toggle">
            <DToggleSwitch
              @state={{this.state.enabled}}
              disabled={{this.loading}}
              {{on "click" this.toggleEnabled}}
            />
            <span>{{i18n "discord_chat_bridge.admin.enabled"}}</span>
          </label>
          <DButton
            @action={{this.testConnection}}
            @label="discord_chat_bridge.admin.test_connection"
            @icon="plug"
            @isLoading={{this.loading}}
          />
          <DButton
            @action={{this.reconnect}}
            @label="discord_chat_bridge.admin.reconnect"
            @icon="arrows-rotate"
            @isLoading={{this.loading}}
          />
          {{#if this.testResult}}
            <span class="success">{{i18n
                "discord_chat_bridge.admin.connected_as"
                bot=this.testResult
              }}</span>
          {{/if}}
        </div>

        <div class="control-group discord-chat-bridge-secret">
          <label for="discord-chat-bridge-token">{{i18n
              "discord_chat_bridge.admin.token"
            }}</label>
          <div class="controls">
            <input
              id="discord-chat-bridge-token"
              type="password"
              autocomplete="new-password"
              value={{this.botToken}}
              placeholder={{i18n "discord_chat_bridge.admin.token_placeholder"}}
              disabled={{this.state.token_managed_by_environment}}
              {{on "input" this.setBotToken}}
            />
            <DButton
              @action={{this.saveToken}}
              @label="discord_chat_bridge.admin.save_token"
              @disabled={{or
                this.loading
                this.state.token_managed_by_environment
              }}
              class="btn-primary"
            />
            <span class="discord-chat-bridge-secret__state">
              {{if
                this.state.token_present
                (i18n "discord_chat_bridge.admin.token_configured")
                (i18n "discord_chat_bridge.admin.token_missing")
              }}
            </span>
          </div>
        </div>
      </div>

      <div class="discord-chat-bridge-section">
        <h3>{{i18n "discord_chat_bridge.admin.mappings"}}</h3>
        {{#if this.hasMappings}}
          <div class="discord-chat-bridge-table-wrap">
            <table class="d-table discord-chat-bridge-mappings">
              <thead>
                <tr>
                  <th>{{i18n
                      "discord_chat_bridge.admin.discord_guild_channel"
                    }}</th>
                  <th>{{i18n "discord_chat_bridge.admin.chat_channel"}}</th>
                  <th>{{i18n "discord_chat_bridge.admin.direction"}}</th>
                  <th>{{i18n "discord_chat_bridge.admin.health"}}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {{#each this.state.mappings as |mapping|}}
                  <tr class={{unless mapping.enabled "is-disabled"}}>
                    <td><strong>{{mapping.discord_guild_id}}</strong><br
                      />{{mapping.discord_channel_id}}</td>
                    <td>{{mapping.chat_channel_id}}</td>
                    <td>{{i18n
                        (concat
                          "discord_chat_bridge.admin.directions."
                          mapping.direction
                        )
                      }}</td>
                    <td>
                      {{#if mapping.last_error_at}}
                        <span
                          class="is-unhealthy"
                          title={{mapping.last_error_message}}
                        >{{i18n "discord_chat_bridge.admin.error"}}</span>
                      {{else}}
                        <span class="is-healthy">{{if
                            mapping.enabled
                            (i18n "discord_chat_bridge.admin.ready")
                            (i18n "discord_chat_bridge.admin.disabled")
                          }}</span>
                      {{/if}}
                    </td>
                    <td>
                      {{#if mapping.enabled}}
                        <DButton
                          @action={{fn this.testMapping mapping}}
                          @label="discord_chat_bridge.admin.test_mapping"
                          @icon="plug"
                          @disabled={{this.loading}}
                          class="btn-small"
                        />
                        <DButton
                          @action={{fn this.disableMapping mapping}}
                          @label="discord_chat_bridge.admin.delete"
                          @icon="ban"
                          @disabled={{this.loading}}
                          class="btn-danger btn-small"
                        />
                      {{else}}
                        <DButton
                          @action={{fn this.enableMapping mapping}}
                          @label="discord_chat_bridge.admin.enable"
                          @icon="play"
                          @disabled={{this.loading}}
                          class="btn-primary btn-small"
                        />
                      {{/if}}
                    </td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{else}}
          <p class="alert alert-info">{{i18n
              "discord_chat_bridge.admin.no_mappings"
            }}</p>
        {{/if}}

        <form
          class="discord-chat-bridge-mapping-form"
          {{on "submit" this.createMapping}}
        >
          <label>
            <span>{{i18n "discord_chat_bridge.admin.guild_id"}}</span>
            <input
              required
              value={{this.guildId}}
              {{on "input" this.setGuildId}}
            />
          </label>
          <label>
            <span>{{i18n "discord_chat_bridge.admin.discord_channel_id"}}</span>
            <input
              required
              value={{this.discordChannelId}}
              {{on "input" this.setDiscordChannelId}}
            />
          </label>
          <label>
            <span>{{i18n "discord_chat_bridge.admin.chat_channel_id"}}</span>
            <input
              required
              type="number"
              min="1"
              value={{this.chatChannelId}}
              {{on "input" this.setChatChannelId}}
            />
          </label>
          <label>
            <span>{{i18n "discord_chat_bridge.admin.direction"}}</span>
            <select value={{this.direction}} {{on "change" this.setDirection}}>
              {{#each this.directions as |value|}}
                <option value={{value}}>{{i18n
                    (concat "discord_chat_bridge.admin.directions." value)
                  }}</option>
              {{/each}}
            </select>
          </label>
          <label class="discord-chat-bridge-mapping-form__webhook">
            <span>{{i18n "discord_chat_bridge.admin.webhook_url"}}</span>
            <input
              type="password"
              autocomplete="off"
              value={{this.webhookUrl}}
              placeholder={{i18n
                "discord_chat_bridge.admin.webhook_placeholder"
              }}
              {{on "input" this.setWebhookUrl}}
            />
          </label>
          <DButton
            @type="submit"
            @label="discord_chat_bridge.admin.add_mapping"
            @icon="plus"
            @isLoading={{this.loading}}
            class="btn-primary"
          />
        </form>
      </div>
    </section>
  </template>
}
