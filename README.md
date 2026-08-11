# Discourse Discord Chat Bridge

`discourse-discord-chat-bridge` maps Discord guild text channels one-to-one with Discourse Chat channels and mirrors message creation, edits, deletion, replies, and attachments in either or both directions.

Discord people are not provisioned as Discourse users. Every Discord-origin message is a genuine `Chat::Message` owned by one non-login technical bot (`user_id = -10001`). A plugin identity row and per-message presentation snapshot make the Discord name and avatar visible in Chat. This preserves Chat search and moderation behavior without manufacturing accounts.

## Architecture

```text
Discord Gateway v10
  -> supervised Discourse plugin demon
  -> normalized Sidekiq jobs
  -> sequence-aware event state
  -> inbound reconciliation
  -> ChatSDK / Chat service objects
  -> PostgreSQL mappings and identities

Discourse Chat events
  -> Sidekiq jobs
  -> Discord incoming webhook REST API
  -> PostgreSQL delivery state and message mappings
```

The long-running Gateway connection uses Discourse's current `register_demon_process` API. Pitchfork supervises one demon per application host and checks it every 60 seconds. A renewable, owner-token Redis lease elects one active Gateway consumer across hosts. Losing the lease closes the connection. Database uniqueness and message/event state provide correctness independently of the lease.

This repository is the complete application. It has no Node service, external database, or companion deployment.

## Supported Features

- Any number of one-to-one channel mappings.
- `bidirectional`, `discord_to_discourse`, and `discourse_to_discord` directions.
- Discord `MESSAGE_CREATE`, `MESSAGE_UPDATE`, `MESSAGE_DELETE`, and `MESSAGE_DELETE_BULK`.
- Discourse Chat create, edit, and trash events.
- Stable Discord identities keyed only by immutable user snowflake.
- Per-message historical display-name snapshots; avatars follow the identity's current cached avatar.
- Real Discord avatars cached as Discourse uploads, with controlled CDN fallback.
- Native Discourse Chat replies when the referenced Discord message is mapped.
- Compact linked reply context for Discourse replies sent through Discord webhooks.
- Native Discourse uploads for safe Discord attachments.
- Discord webhook username/avatar overrides for Discourse users.
- Persistent loop protection, delivery state, tombstones, and sequence-aware race handling.
- Gateway heartbeat ACK enforcement, resume, invalid-session handling, backoff, jitter, and graceful shutdown.
- Admin-only health, credential, mapping, connectivity, and reconnect controls.
- Conservative scheduled tombstone and retention cleanup.

## Deliberate Limitations

- Discord controls edits and deletion of Discord-origin content. A local moderator edit to its mirrored Chat row remains local and is not sent to Discord. Normal operation does not require `MANAGE_MESSAGES`.
- Discord's documented incoming webhook Execute API does not accept `message_reference`. Discourse replies therefore include a compact author/excerpt and a jump link when the target has a Discord mapping. The bridge does not sacrifice webhook identity overrides to emulate native replies through a bot.
- Updating a webhook message cannot update that message's per-message username or avatar. Content and retained attachment IDs are updated.
- Cross-platform reactions, typing, presence, read receipts, DMs, forum posts, voice, roles/groups, automatic channel creation, Discord thread creation, and history import are not implemented.
- Long Discourse messages are posted with a preview and `message.txt` attachment on create. A later edit is truncated to Discord's 2,000-character limit because editing cannot add that deterministic text attachment without replacing existing files.
- Discord signed attachment URLs expire. Successful imports are native Discourse uploads; safe CDN links are only a failure fallback.
- Private Discourse avatar URLs cannot be fetched by Discord. Configure `discord_chat_bridge_public_base_url` and `discord_chat_bridge_avatar_fallback_url` for a public fallback.
- An incoming webhook POST that times out after connection is fundamentally ambiguous because Discord offers no documented idempotency key for webhook execution. The bridge marks the delivery `ambiguous` and does not retry automatically, preventing duplicates. Resolve these entries operationally after inspecting Discord.

## Discord Setup

1. Open the [Discord Developer Portal](https://discord.com/developers/applications) and create an application.
2. Add a bot to the application.
3. On the Bot page, enable the privileged **Message Content Intent**. Approval may be required for sufficiently large/verified applications.
4. Generate an OAuth2 installation URL with the `bot` scope.
5. Grant the bot only the permissions listed below in source channels.
6. Install the bot into the target guild.
7. In each outbound destination channel, create one incoming webhook under **Edit Channel > Integrations > Webhooks**.
8. Copy each webhook URL once into the bridge mapping form. The URL is write-only after submission.

Do not grant Administrator.

### Gateway Intents

The plugin identifies with exactly:

| Intent            |     Value | Reason                                    |
| ----------------- | --------: | ----------------------------------------- |
| `GUILDS`          |  `1 << 0` | Guild/channel lifecycle context           |
| `GUILD_MESSAGES`  |  `1 << 9` | Guild message create/update/delete events |
| `MESSAGE_CONTENT` | `1 << 15` | Message body and attachment fields        |

Combined intent value: `33281`. `GUILD_MEMBERS`, presence, and typing intents are not requested.

### Required Permissions

For Discord to Discourse:

- `VIEW_CHANNEL` in each mapped source channel.
- `READ_MESSAGE_HISTORY` so a defensive REST fetch can complete a partial or uncached `MESSAGE_UPDATE`.

For Discourse to Discord, the incoming webhook token is the posting capability. The bot does not need `SEND_MESSAGES` merely to execute that webhook.

Optional:

- `MANAGE_WEBHOOKS` is needed only if an administrator or bot creates/manages webhooks. Version 1 accepts an existing webhook URL and does not require this permission on the bridge bot.
- `MANAGE_MESSAGES` is not used or required.

## Installation

Add the plugin to the Discourse container configuration, normally `/var/discourse/containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/Bjorkan/Discourse-Chat-Discord.git discourse-discord-chat-bridge
```

Rebuild the container:

```sh
cd /var/discourse
./launcher rebuild app
```

The rebuild installs the pinned Ruby Gateway dependencies, runs the migration and SeedFu fixture, compiles frontend assets, and starts the supervised Gateway demon. The bot token can be managed in the admin UI, but production operators should prefer environment injection:

```yaml
env:
  DISCORD_CHAT_BRIDGE_BOT_TOKEN: "your-bot-token"
```

An environment token shadows the encrypted plugin-store value and makes the admin token field read-only.

## Configuration

1. Enable Discourse Chat and create the destination Chat channels normally.
2. Visit **Admin > Plugins > Discord Chat Bridge > Overview**.
3. Enter the bot token, unless supplied through `DISCORD_CHAT_BRIDGE_BOT_TOKEN`.
4. Use **Test Discord connection** and confirm the expected bot identity.
5. Add the guild snowflake, Discord channel snowflake, Discourse Chat channel ID, direction, and webhook URL.
6. A webhook URL is required only for directions that include Discourse to Discord.
7. Use **Test mapping** to verify that both channel IDs remain reachable.
8. Enable the bridge and request reconnect if the demon was already waiting.

Mappings begin at activation time. No historical Discord messages are imported. Disabling a mapping stops future synchronization and leaves historical messages and audit mappings intact.

Settings under **Admin > Settings > Plugins** control attachment limits, tombstone retention, bot/webhook inclusion, avatar fallback, public URL, and Gateway autostart.

## Gateway Operations

There is no independent service to install. Pitchfork owns the plugin demon and gives it the process title `discourse discord_chat_bridge_gateway`.

Start or restart the complete Discourse application:

```sh
cd /var/discourse
./launcher start app
./launcher restart app
```

Stop it cleanly:

```sh
cd /var/discourse
./launcher stop app
```

Inspect the process:

```sh
cd /var/discourse
./launcher enter app
ps aux | grep discord_chat_bridge_gateway
```

Monitor logs:

```sh
cd /var/discourse
./launcher logs app
```

The demon handles `TERM` and `INT`, closes the WebSocket, and releases its Redis lease. Pitchfork restarts an unexpectedly dead demon during its supervision check. In multi-host installations every host has a standby process, but only the Redis lease holder connects.

The admin **Request reconnect** action closes the current socket and attempts `RESUME`; it does not restart Pitchfork. Use `./launcher restart app` for process-level restart.

## Health and Troubleshooting

The admin page reports:

- Gateway connected/connecting/standby state.
- Session resumability and heartbeat acknowledgement time.
- Last Gateway event and event type.
- Last safe error classification.
- Enabled mappings and mapping errors.
- Ambiguous outbound deliveries.

Common failures:

| Symptom                      | Check                                                                                                |
| ---------------------------- | ---------------------------------------------------------------------------------------------------- |
| Gateway waits                | Bridge enabled, token configured, Gateway autostart enabled, and at least one inbound mapping active |
| Close code `4004`            | Bot token is invalid; replace it and reconnect                                                       |
| Close code `4014`            | Message Content intent is not enabled/approved                                                       |
| Messages have empty content  | Message Content intent is missing                                                                    |
| Mapping test returns 403/404 | Bot lacks channel visibility/history or was removed                                                  |
| Webhook returns 404          | Webhook was deleted; disable and recreate the mapping with a new URL                                 |
| Avatar absent in Discord     | Discourse URL is private; configure a public fallback                                                |
| `ambiguous` count increases  | Inspect Discord for the message, then reconcile manually before retrying                             |

Structured log records start with `plugin=discourse-discord-chat-bridge` and include operation, direction, mapping/message IDs, result, and error class where available. Message content and credentials are not logged at INFO.

## Security

- Stored bot and webhook tokens are encrypted and signed with a key derived from Discourse `secret_key_base` and a plugin-specific purpose.
- Tokens are never serialized to the browser. Admin responses expose only `token_present` and `webhook_configured` booleans.
- Prefer `DISCORD_CHAT_BRIDGE_BOT_TOKEN` so the bot token never enters PostgreSQL.
- Discord content is untrusted. Every `@` is neutralized before Discourse mention processing.
- Discord receives `allowed_mentions: { parse: [] }` on creates and edits, so visible mention text cannot ping users, roles, or everyone.
- Attachments are accepted only from structured Discord attachment fields and exact HTTPS hosts `cdn.discordapp.com` or `media.discordapp.net`, on port 443, under `/attachments/`.
- `FileHelper.download` adds DNS/IP SSRF validation, strict timeouts, no redirects, and a streamed hard byte limit. `UploadCreator` applies Discourse extension, MIME, image, SVG, and size validations.
- Webhook URLs accept only canonical `https://discord.com/api[/vN]/webhooks/{id}/{token}` URLs with no userinfo or custom port.
- Admin endpoints use `Admin::AdminController` plus `StaffConstraint`. Avatar endpoints contain no secrets and expose only controlled cached/CDN avatar data.
- Never place tokens in mapping names, logs, screenshots, or support posts.

## Persistence, Retention, and Backups

PostgreSQL stores channel mappings, encrypted webhook capabilities, identities, message mappings, snapshots, delivery state, and Gateway event tombstones. Redis stores ephemeral health, rate-limit buckets, Gateway resume state, and the leader lease.

Discourse backups include plugin PostgreSQL tables and PluginStore credentials. Keep the same `secret_key_base` when restoring; changing it makes encrypted credentials unreadable, requiring token re-entry. Redis state does not need backup. The Gateway identifies a fresh session when resume state is absent.

A daily job removes event/tombstone state older than `discord_chat_bridge_tombstone_retention_days` and detaches mappings from Chat rows removed by retention. Historical visible messages are never deleted merely because a channel mapping is disabled.

## Upgrade Procedure

1. Back up Discourse.
2. Review this plugin's release notes and current Discourse compatibility.
3. Pull through the normal container rebuild; do not update code inside a running container.
4. Run `./launcher rebuild app`.
5. Confirm the migration completed, the demon process exists, and the admin health page reconnects/resumes.
6. Test one create/edit/delete in each direction on a non-production mapping before broad rollout.

The compatibility baseline used for version 1 was Discourse `tests-passed` commit `f3c568cfd26a427e9cae32063732a56bc7d334b9` (2026-08-08 UTC), including `ChatSDK::Message`, `Chat::UpdateMessage`, `Chat::TrashMessage`, current Chat serializers/events, and Pitchfork demon supervision. Discord behavior was checked against the official Gateway v10, Message, Webhook, Allowed Mentions, and Rate Limits documentation.

## Development and Tests

Place or symlink this repository at `plugins/discourse-discord-chat-bridge` in a current Discourse checkout. From the Discourse root:

```sh
LOAD_PLUGINS=1 bundle exec rspec plugins/discourse-discord-chat-bridge/spec
bin/rake "plugin:qunit[discourse-discord-chat-bridge]"
bin/lint plugins/discourse-discord-chat-bridge
```

Run migrations in development/test as normal:

```sh
bundle exec rails db:migrate
RAILS_ENV=test bundle exec rails db:migrate
```

The GitHub workflow invokes Discourse's maintained reusable plugin workflow for Ruby specs, frontend tests, and lint against supported branches.

## API References

- [Discord Gateway](https://docs.discord.com/developers/events/gateway)
- [Discord Gateway events](https://docs.discord.com/developers/events/gateway-events)
- [Discord Message resource](https://docs.discord.com/developers/resources/message)
- [Discord Webhook resource](https://docs.discord.com/developers/resources/webhook)
- [Discord rate limits](https://docs.discord.com/developers/topics/rate-limits)
- [Discourse Chat SDK source](https://github.com/discourse/discourse/tree/tests-passed/plugins/chat/lib/chat_sdk)
- [Discourse plugin API](https://github.com/discourse/discourse/blob/tests-passed/lib/plugin/instance.rb)
