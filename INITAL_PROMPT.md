You are implementing a production-quality **bidirectional Discord ↔ Discourse Chat bridge** as a **single Discourse plugin**.

You have no prior context about this project. Treat this document as the complete product and architecture specification.

Your task is not to produce a design document or proof of concept. You must inspect the current Discourse codebase, create the plugin, implement the bridge, write migrations and tests, provide an admin UI/configuration, and produce installation and operational documentation.

# 1. Product goal

Build a Discourse plugin that maps one or more Discord text channels to Discourse Chat channels and mirrors conversations in both directions.

The desired experience is:

```text
Discord
────────────────────────────
[avatar] Alice
Hello everyone

[avatar] Bob
↳ Alice
Hi!
```

and in Discourse Chat:

```text
Discourse Chat
────────────────────────────
[avatar] Alice   DISCORD
Hello everyone

[avatar] Bob     DISCORD
↳ Alice
Hi!
```

A normal Discourse user writing in Discourse Chat should appear in Discord approximately as:

```text
[Discourse avatar] Charlie
Message written in Discourse
```

The bridge must preserve human identity visually without creating a Discourse account for every Discord user.

# 2. Hard architectural constraint

Everything must be delivered in **one Discourse plugin repository**.

Do not create:

* a separate Node.js service
* a separate bridge repository
* an external database
* a separate web application
* a separate microservice

Ruby code, JavaScript/Glimmer UI code, migrations, background jobs, Gateway integration, Discord REST integration, admin UI, tests, configuration, and documentation must all live inside the Discourse plugin.

A dedicated runtime process shipped by the plugin is acceptable and preferred for the persistent Discord Gateway connection.

For example:

```text
plugins/discourse-discord-chat-bridge/
├── plugin.rb
├── app/
├── lib/
├── db/
├── spec/
├── assets/
├── config/
└── bin/
    └── discord_gateway
```

The Gateway executable/process is still part of the plugin.

Do NOT maintain a permanent Discord WebSocket connection inside:

* a Unicorn web worker
* every Rails process
* an infinite Sidekiq job

That would create duplicate connections and poor lifecycle behavior.

Instead, implement a dedicated plugin-owned Gateway worker/process that boots the Discourse environment, connects to Discord, and enqueues normal Discourse/Sidekiq jobs for event processing.

Use the standard process supervision mechanism appropriate for the current supported Discourse deployment architecture. Document exactly how it is started, stopped, restarted, monitored, and upgraded.

If current Discourse provides a cleaner officially supported mechanism for a plugin-owned long-running process, use that instead.

# 3. Verify current APIs before coding

Do not rely on historical Discourse or Discord API knowledge.

Inspect the actual current source/documentation before implementation.

In particular verify the current behavior and signatures of:

```text
Discourse:
Chat::CreateMessage
Chat::UpdateMessage
Chat::TrashMessage
Chat::Message
Chat::MessageSerializer
Chat::MessageUserSerializer
Chat::WebhookEvent
Chat::IncomingWebhook
Chat::Publisher
Chat::MessageReaction
Chat message processing / mentions
Chat reply handling
Chat thread handling
plugin serializer extensions
plugin frontend extension APIs
plugin admin APIs
secret/encrypted storage facilities
plugin gem/dependency conventions
```

Also verify the current Discord API for:

```text
Gateway
Gateway intents
MESSAGE_CREATE
MESSAGE_UPDATE
MESSAGE_DELETE
MESSAGE_DELETE_BULK
message references
attachments
Discord REST rate limits
incoming webhooks
Execute Webhook
Edit Webhook Message
Delete Webhook Message
allowed_mentions
Discord CDN attachment URLs
Gateway session resume
```

Do not use deprecated Discourse Chat classes such as historical `Chat::ChatMessageCreator` APIs if the current code uses newer service objects.

# 4. High-level architecture

The plugin should implement this architecture:

```text
                         DISCOURSE PLUGIN
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   Discord Gateway process                                  │
│            │                                               │
│            │ normalized events                             │
│            ▼                                               │
│      Sidekiq jobs                                          │
│            │                                               │
│            ▼                                               │
│      Bridge services                                       │
│            │                                               │
│            ├────► Discourse Chat services                  │
│            │                                               │
│            └────► Discord REST/Webhook API                 │
│                                                            │
│      PostgreSQL                                            │
│      ├── channel mappings                                  │
│      ├── Discord identities                                │
│      ├── message mappings                                  │
│      └── processed event/idempotency state                 │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

There are two paths:

```text
Discord → Gateway → plugin job → Discourse Chat
```

and:

```text
Discourse Chat → plugin event hook → job → Discord webhook
```

# 5. Identity model: critical requirement

Do **not** create one Discourse `User` per Discord user.

This is a hard requirement.

Do not create usernames such as:

```text
discord_123456789
external_alice
bridge_bob
```

as real Discourse users.

Instead, use **one dedicated technical Discourse bridge actor** for messages originating from Discord.

The actual Discord identity must be stored separately as bridge metadata.

Conceptually:

```text
Chat::Message
user_id = technical_bridge_user_id

DiscordBridge::Identity
discord_user_id = 123456789012345678
display_name = "Alice"
username = "alice"
avatar = ...
```

and:

```text
DiscordBridge::Message
chat_message_id = 501
discord_message_id = 987654321
identity_id = 42
origin = "discord"
```

The Discourse UI must render the external Discord identity instead of the underlying technical bridge actor.

# 6. Discord identity table

Implement a model similar to:

```text
DiscordChatBridge::Identity
---------------------------
id
discord_user_id
discord_username
discord_global_name
display_name
avatar_hash
avatar_url
avatar_upload_id
last_synced_at
created_at
updated_at
```

Use the immutable Discord user snowflake as the external identity key.

For guild messages, presentation priority should roughly be:

```text
guild nickname
→ global display name
→ Discord username
```

but confirm current Discord semantics.

Names are presentation only.

Never use a display name as the identity key.

A renamed Discord user must continue using the same identity record.

# 7. Dedicated Discourse bridge actor

Create or provision one dedicated bot/service user according to current recommended Discourse plugin patterns.

Requirements:

* not used by humans
* no normal password login if this can be avoided
* minimum required privileges
* only the plugin should use it
* should not appear visually as the author of Discord-origin messages
* should own Discord-origin `Chat::Message` rows so create/edit/delete permissions remain consistent

Do not use multiple technical actors for individual Discord users.

Do not use the main Discourse system account unless that is clearly the safest current Discourse pattern. Prefer a dedicated plugin bot actor if supported.

# 8. External identity metadata in Discourse Chat

The browser must receive explicit metadata indicating that a message came from Discord.

For example:

```json
{
  "external_author": {
    "source": "discord",
    "id": "123456789012345678",
    "display_name": "Alice",
    "username": "alice",
    "avatar_url": "/discord-chat-bridge/avatar/123456789012345678"
  }
}
```

Use a plugin-specific model/association and serializer extension where possible.

Investigate whether Discourse Chat's existing webhook identity concepts can be reused cleanly, but do not abuse core database tables if a plugin-owned model provides a cleaner implementation.

The final serialized model should make external authors first-class presentation metadata.

# 9. Discourse Chat UI

A Discord-origin message should look approximately like:

```text
[avatar] Alice   DISCORD
Hello
```

or:

```text
[avatar] Alice   via Discord
Hello
```

Requirements:

* show Discord display name
* show Discord avatar
* clearly identify the external source
* do not display the technical bridge username
* do not open a local Discourse user card when clicking the external identity
* optionally allow clicking the source indicator to show harmless external identity information
* never imply that the Discord person has a local Discourse account

Use supported Discourse plugin extension mechanisms.

Do not patch Discourse core files directly.

# 10. Message grouping is critical

Discourse Chat normally groups adjacent messages based partly on `message.user.id`.

That is incorrect for this bridge because all Discord-origin messages technically share one bridge actor.

These two messages:

```text
Alice:
Message A

Bob:
Message B
```

must NOT be visually grouped as the same author.

The grouping identity for bridged messages must effectively become:

```text
external source + external user ID
```

So:

```text
discord:123 → Alice
discord:456 → Bob
```

are different authors.

But:

```text
discord:123 → message A
discord:123 → message B
```

may still use normal Discourse consecutive-message grouping rules.

Modify the relevant Chat presentation logic using supported plugin APIs.

Write explicit regression tests for this.

# 11. Channel mappings

Provide an admin-configurable mapping model:

```text
DiscordChatBridge::ChannelMapping
---------------------------------
id
discord_guild_id
discord_channel_id
chat_channel_id
direction
enabled
discord_webhook_id
encrypted_discord_webhook_token
created_at
updated_at
```

Supported direction values:

```text
bidirectional
discord_to_discourse
discourse_to_discord
```

For enabled mappings, enforce one-to-one relationships unless there is a compelling technical reason otherwise.

At minimum:

```text
one Discord channel → one Discourse Chat channel
one Discourse Chat channel → one Discord channel
```

Enforce this in both model validation and database constraints.

Do not automatically create Discord or Discourse channels.

# 12. Admin UI

Add a proper Discourse admin interface under the plugin.

The administrator should be able to:

* enable/disable the bridge
* configure the Discord bot token
* inspect bot/Gateway status
* add/remove channel mappings
* choose mapping direction
* configure/create Discord outbound webhook
* test Discord connectivity
* test Discourse Chat mapping
* see the last successful Gateway event
* see the last synchronization error
* restart/reconnect the Gateway integration if reasonably supported
* inspect mapping health without exposing secrets

Secrets must never be returned to the browser after storage.

Use current Discourse secret/encrypted storage mechanisms.

# 13. Discord Gateway

Discord → Discourse requires receiving normal Discord guild message events.

Implement a resilient Gateway client.

Subscribe only to the intents actually required.

For normal guild text messages this will likely include:

```text
GUILDS
GUILD_MESSAGES
MESSAGE_CONTENT
```

but verify against the current Discord documentation.

Do not request privileged intents that are unnecessary.

The Gateway client must correctly implement or delegate:

* Gateway URL discovery if needed
* IDENTIFY
* heartbeat
* heartbeat acknowledgement handling
* sequence numbers
* reconnect
* RESUME
* invalid sessions
* exponential reconnect backoff
* authentication failures
* graceful shutdown
* network timeouts
* reconnect jitter
* session state persistence where useful

Prefer a mature maintained Ruby Discord/Gateway library if one is compatible with the current Discourse Ruby stack.

If adding a gem:

* follow current Discourse plugin dependency conventions
* pin versions appropriately
* include required checksum metadata if Discourse requires it
* avoid pulling in a huge framework merely for three Gateway events

If implementing the Gateway client directly, keep it minimal and extensively test it.

Do not enable Gateway compression unless necessary.

# 14. Gateway process singleton behavior

There must never be multiple active Gateway consumers processing the same application instance unintentionally.

Use both deployment architecture and a Redis-backed leader/lock mechanism where appropriate.

If a second process accidentally starts:

```text
process A → owns gateway lock
process B → does not connect
```

The lock must have safe expiry/renewal behavior.

Gateway event handling itself must still be idempotent because locks alone are insufficient.

# 15. Gateway process responsibilities

The Gateway process should do as little application work as possible.

It should:

```text
receive Discord event
→ validate basic shape
→ filter clearly irrelevant guild/channel events
→ enqueue Sidekiq job
→ return to Gateway loop
```

Do not perform expensive:

* file downloads
* image processing
* Discourse Chat writes
* attachment uploads

inside the WebSocket event loop.

# 16. Discord → Discourse CREATE

Handle `MESSAGE_CREATE`.

Ignore by default:

* messages outside configured channels
* the bridge application's own bot messages
* webhook messages generated by this plugin
* other webhook messages unless explicitly enabled
* other bots unless explicitly enabled
* unsupported Discord system messages

For an accepted message:

1. Resolve channel mapping.
2. Establish idempotency using Discord message ID.
3. Resolve/update external Discord identity.
4. Normalize text.
5. Neutralize unsafe mentions.
6. Download/process supported attachments.
7. Resolve reply relationship.
8. Create `Chat::Message`.
9. Attach external author metadata.
10. Store message mapping.
11. Commit atomically where practical.

Use current:

```ruby
Chat::CreateMessage
```

or its current replacement.

Do not manipulate Chat tables directly unless there is no supported service API.

# 17. Discord → Discourse EDIT

Handle `MESSAGE_UPDATE`.

Use:

```text
discord_message_id
      ↓
message mapping
      ↓
chat_message_id
      ↓
Chat::UpdateMessage
```

A Discord edit must edit the existing Discourse Chat message.

Do not create:

```text
Alice edited their message:
...
```

as a new message.

Handle partial Discord `MESSAGE_UPDATE` payloads correctly. Fetch the full Discord message over REST if necessary.

Repeated delivery of the same state must be harmless.

# 18. Discord → Discourse DELETE

Handle:

```text
MESSAGE_DELETE
MESSAGE_DELETE_BULK
```

Resolve the mapping and trash/delete the corresponding Discourse Chat message using the current Chat service API, likely:

```ruby
Chat::TrashMessage
```

Use the same technical bridge actor that owns the Discord-origin message.

Do not leave orphaned message mappings.

Retain mapping tombstones if they are useful for replay/idempotency.

# 19. Discord → Discourse replies

Discord replies should become native Discourse Chat replies whenever possible.

Example:

```text
Discord message D100
        ↕
Discourse message C500
```

Then a Discord message replying to `D100` should create:

```ruby
in_reply_to_id: C500
```

when creating the Discourse message.

If the referenced Discord message was not bridged, degrade gracefully:

* post the new message
* optionally include a compact quoted reference
* never fail the entire message

# 20. Discord attachments → Discourse Uploads

Support at minimum:

* images
* ordinary files
* audio/video where allowed by Discourse

Prefer native Discourse `Upload` objects rather than permanent Discord CDN hotlinks.

Security requirements:

* enforce maximum size before downloading when metadata provides size
* enforce a streamed hard byte limit while downloading
* validate expected Discord attachment/CDN hostnames
* never treat arbitrary user-provided URLs as attachment download targets
* use strict HTTP timeouts
* follow redirects only according to a safe policy
* respect Discourse allowed extensions/types
* avoid loading large files fully into memory
* clean up temp files

If upload fails, degrade to a safe Discord attachment URL or a short explanatory fallback instead of dropping the entire message.

# 21. Mentions: safe by default

Do not allow arbitrary text originating from Discord to become real Discourse mentions automatically.

For example, Discord text containing:

```text
@admin
@moderators
@all
@here
```

must not accidentally trigger Discourse notifications.

Neutralize external mentions before Discourse Markdown/mention processing unless an explicit trusted mapping exists.

Do the same in the other direction.

When posting to Discord, always use Discord's `allowed_mentions` structure and default to allowing **no pings** for bridged content.

A future explicit identity-mapping feature may opt individual mentions into cross-platform notification behavior, but that is not part of the first production release.

# 22. Discourse → Discord CREATE

Listen to the current official/plugin-supported Discourse Chat message-created event.

Do not blindly bridge every Chat message.

Skip messages when:

* Chat channel has no enabled mapping
* direction does not include Discourse → Discord
* message originated from Discord
* message was generated by this bridge
* message is otherwise marked loop-protected

For a normal Discourse Chat message:

1. Read raw Chat message content.
2. Resolve mapping.
3. Build Discord-safe content.
4. Resolve Discourse user's visible name.
5. Resolve Discourse avatar URL.
6. Build attachments.
7. Send through the configured Discord incoming webhook.
8. Set `wait=true` so Discord returns the created message.
9. Override webhook `username` per message with the Discourse user's name.
10. Override webhook `avatar_url` per message with the Discourse user's avatar.
11. Set `allowed_mentions` to the safe policy.
12. Store returned Discord message ID.

Conceptually:

```text
Discourse User Charlie
        ↓
Discord webhook execution

username   = "Charlie"
avatar_url = Charlie's avatar
content    = message
```

Do not create one Discord webhook per Discourse user.

Use one webhook per mapped Discord channel and override identity per message.

# 23. Discourse → Discord EDIT

For messages whose origin is Discourse:

```text
Chat message edited
      ↓
lookup mapping
      ↓
Discord webhook message ID
      ↓
Edit Webhook Message
```

Update the existing Discord message.

Do not send a second message stating that it was edited.

Always include the safe `allowed_mentions` behavior during edits as well.

# 24. Discourse → Discord DELETE

For messages whose origin is Discourse:

```text
Chat message trashed
      ↓
lookup mapping
      ↓
Delete Webhook Message
```

Delete the corresponding webhook message from Discord.

Handle an already-deleted Discord message as an idempotent success.

# 25. Important asymmetry: messages originally created on Discord

A normal Discord user's original message is owned by that Discord user.

The bridge cannot simply edit another user's Discord message.

Therefore:

```text
origin = discord
```

has authoritative content lifecycle on the Discord side.

Discord edits/deletes should update Discourse.

If a Discourse moderator edits the mirrored copy of a Discord-origin message, do not attempt an impossible edit of the original Discord user message.

Choose and document a safe policy, preferably:

```text
Discord-origin message:
Discord controls content edits.

Discourse moderator edit:
local-only or rejected/ignored for outbound sync.
```

Moderator deletion may optionally propagate to Discord only if explicitly enabled and the Discord bot has the required moderation permission.

Do not require `MANAGE_MESSAGES` for normal bridge operation.

# 26. Replies from Discourse → Discord

Investigate the current Discord webhook API carefully.

Do not use undocumented fields.

If Discord incoming webhook execution currently supports a true message reference/reply for this use case, use it.

If it does not, preserve the identity-preserving webhook architecture and render a compact reply context instead, for example:

```text
↳ Alice: original excerpt

Reply from Charlie
```

or use a small embed/reference if that produces cleaner Discord UX.

If the original message has a Discord message mapping, include a valid Discord message jump link where appropriate.

Do not abandon per-message username/avatar impersonation merely to get native reply UI.

Document this asymmetry clearly.

# 27. Discourse Chat threads

Do not confuse Discourse Chat threads with Discord channel threads.

For the first version:

* support ordinary Chat messages and reply relationships
* preserve Discourse thread context where reasonable
* do not automatically create Discord threads unless a robust deterministic mapping is implemented
* do not create complex cross-platform thread semantics accidentally

Keep the schema extensible for future thread mapping.

# 28. Loop prevention

Loop prevention is a first-class requirement.

Example dangerous cycle:

```text
Discourse message
→ Discord webhook message
→ Discord Gateway MESSAGE_CREATE
→ Discourse message
→ Discord
→ ...
```

Prevent this at multiple levels.

For Discord Gateway events:

* ignore configured bridge webhook IDs
* ignore bridge bot/application messages where applicable
* check persistent message mapping

For Discourse events:

* store message origin
* do not re-export messages where `origin == discord`
* use persistent mapping checks

Never rely solely on usernames such as "Bridge Bot" to detect loops.

# 29. Message mapping

Use a persistent model similar to:

```text
DiscordChatBridge::MessageMapping
---------------------------------
id
channel_mapping_id

chat_message_id
discord_message_id

origin
  discord
  discourse

discord_identity_id nullable

discord_channel_id
discourse_chat_channel_id

discord_last_edited_at
discourse_last_edited_at

deleted_on_discord_at
deleted_on_discourse_at

created_at
updated_at
```

Database constraints should enforce appropriate uniqueness.

For example:

```text
chat_message_id UNIQUE
discord_channel_id + discord_message_id UNIQUE
```

Do not rely only on application-level uniqueness validations.

# 30. Idempotency

Every externally received event must be safe to process more than once.

Create a processed-event/state mechanism where needed.

For CREATE, Discord's message ID provides a natural idempotency key.

For update/delete operations, repeated identical operations must be harmless.

Gateway reconnect/resume behavior must not cause duplicate Chat messages.

Sidekiq retries must not cause duplicate Discord webhook messages.

For Discourse → Discord create, solve the classic failure case:

```text
POST to Discord succeeds
process crashes before mapping is saved
Sidekiq retries
duplicate Discord message
```

Design for this explicitly as far as Discord's API permits.

At minimum:

* robust transaction/state machine
* retry-aware delivery status
* duplicate detection/reconciliation
* clear logging when an ambiguous network failure occurs

# 31. Ordering and races

Handle races such as:

```text
CREATE queued
EDIT arrives
DELETE arrives
```

before CREATE processing finishes.

Do not assume Sidekiq executes all jobs in exact event order.

Use:

* per-message serialization/locking
* DB row locks
* state reconciliation
* short retry/defer behavior

as appropriate.

A final delete should not resurrect a message because an older edit job executes later.

# 32. Formatting conversion

Discord Markdown and Discourse Markdown overlap but are not identical.

Implement a small explicit conversion layer rather than spreading transformations through event handlers.

For the first version prioritize:

* plain text
* bold
* italic
* inline code
* code blocks
* links
* quotes
* line breaks
* spoiler syntax if practical

Do not attempt an enormous Markdown parser unless required.

Never allow formatting conversion to break mention-safety.

# 33. Avatar handling

## Discord → Discourse

Discord users should display their real Discord avatar where possible.

Do not download/re-upload the avatar for every message.

Cache based on:

```text
discord_user_id
avatar hash
```

Only update when the hash changes.

Prefer a locally stored Discourse `Upload` or a controlled cached/proxy representation.

Have a fallback avatar.

## Discourse → Discord

Use the Discourse user's normal avatar URL as the Discord webhook `avatar_url`.

Ensure the URL is externally reachable by Discord.

If the Discourse site is private or the avatar URL is not externally accessible, provide a documented fallback strategy.

# 34. Reactions

Cross-platform reaction synchronization is **not required for version 1**.

This is intentional.

A reaction made by a Discord user cannot be represented as that human in Discourse without creating a local user, which violates the identity architecture.

Likewise a Discord webhook cannot make a Discord reaction appear as an arbitrary Discourse human.

Therefore:

* Discord reactions remain local to Discord
* Discourse reactions remain local to Discourse
* do not create fake reaction identities
* keep the schema open for future aggregate/reaction features

# 35. Typing indicators and presence

Do not bridge:

* typing indicators
* online presence
* read receipts

They are outside scope.

# 36. Webhook identity on Discord

Use a configured Discord incoming webhook for the Discourse → Discord path.

The webhook must use per-message:

```text
username
avatar_url
```

overrides.

Use `wait=true`.

Store:

```text
webhook ID
webhook token
Discord message ID
```

securely as needed.

Support editing and deleting messages using the same webhook token.

The webhook token is a secret.

Never expose it in logs, serializers, admin JSON responses, exception messages, or frontend JavaScript.

# 37. Discord webhook provisioning

Support one of these clean models:

A. Administrator pastes an existing webhook URL for the mapped channel.

or preferably, if safe:

B. Plugin creates/manages a webhook using the Discord bot if the bot has `MANAGE_WEBHOOKS`.

Do not require `MANAGE_WEBHOOKS` merely to consume Discord messages.

If automatic webhook creation is offered, make it optional and clearly describe the extra permission.

# 38. Permissions

Follow least privilege.

For normal bidirectional bridging, determine and document the minimum Discord permissions required.

The bot should not receive administrator permissions.

Do not require moderation permissions unless optional moderation synchronization is enabled.

Document separately:

```text
required Gateway intents
required guild/channel permissions
optional permissions
```

# 39. Security

Treat Discord-origin content as untrusted user input.

Required protections include:

* mention sanitization
* upload size limits
* attachment URL validation
* HTTP timeouts
* safe redirect handling
* MIME/extension checks
* webhook token secrecy
* bot token secrecy
* rate limiting where appropriate
* no arbitrary URL fetching
* no arbitrary HTML injection
* no unsafe serializer HTML
* no secrets in logs

If the plugin exposes any HTTP endpoints, protect them with appropriate Discourse authentication or cryptographic validation.

# 40. Rate limits

Implement Discord REST rate-limit handling correctly.

Do not simply sleep for arbitrary fixed durations.

Respect:

* response headers
* HTTP 429
* retry-after
* route/bucket behavior where appropriate

Queue outbound operations and retry responsibly.

Also account for Discourse-side message/Chat limits.

# 41. Failure model

Temporary failures should retry.

Examples:

```text
Discord API 500
network timeout
Gateway disconnect
temporary CDN failure
```

Permanent failures should not retry forever.

Examples:

```text
Discord channel no longer exists
webhook deleted
bot removed from guild
mapping deleted
invalid webhook token
unsupported attachment
```

Provide useful admin health/error information.

# 42. Observability

Use structured logging.

Useful fields:

```text
operation
direction
channel_mapping_id
discord_guild_id
discord_channel_id
discord_message_id
chat_channel_id
chat_message_id
origin
attempt
result
error_class
```

Do not log full message content at INFO level by default.

Never log credentials.

# 43. Health monitoring

Expose plugin/admin health information such as:

```json
{
  "enabled": true,
  "gateway": {
    "connected": true,
    "session_resumable": true,
    "last_event_at": "..."
  },
  "discord_rest": {
    "reachable": true
  },
  "mappings": {
    "enabled": 3,
    "errors": 0
  },
  "queue": {
    "failed_recently": 0
  }
}
```

Do not expose this publicly unless intentionally designed as a safe unauthenticated health endpoint.

# 44. Search

Discord-origin messages must remain genuine `Chat::Message` records so normal Discourse Chat search can index the message content.

External Discord identity should be rendered in results where practical.

Do not create fake forum posts or topics merely to make search work.

# 45. Retention

Respect Discourse Chat retention behavior.

Message-mapping cleanup must account for Chat messages that disappear because of retention.

Do not allow mapping tables to grow forever with dangling rows.

Implement a scheduled cleanup job with conservative retention/tombstone behavior.

# 46. Deleting a channel mapping

Deleting/disabling a mapping must not delete historical messages automatically.

It should stop future synchronization.

Existing message mappings can be retained for audit/idempotency or cleaned up according to documented policy.

# 47. Initial sync

Do not silently import an entire Discord channel history when enabling a mapping.

Default behavior:

```text
bridge messages from the point the mapping becomes active
```

If optional history backfill is implemented, it must:

* be explicit
* be bounded
* preserve chronology
* be idempotent
* respect Discord rate limits
* clearly identify imported messages

History backfill is not required for version 1.

# 48. Tests

Write meaningful automated tests.

## Discord → Discourse

Test:

* MESSAGE_CREATE
* duplicate MESSAGE_CREATE
* MESSAGE_UPDATE
* partial MESSAGE_UPDATE
* MESSAGE_DELETE
* MESSAGE_DELETE_BULK
* ignored wrong channel
* ignored bot
* ignored own webhook
* ignored loop event
* nickname/display-name selection
* avatar update
* reply resolution
* reply to unmapped message
* image attachment
* oversized attachment
* invalid attachment URL
* mention sanitization
* race: edit before create job finishes
* race: delete before create job finishes
* Gateway reconnect
* Gateway resume
* duplicate Gateway delivery

## Discourse → Discord

Test:

* Chat message create
* webhook username override
* webhook avatar override
* allowed_mentions safety
* message ID storage
* Chat edit → webhook edit
* Chat delete → webhook delete
* already-deleted Discord message
* retry after rate limit
* Discord 500 retry
* ambiguous network failure
* skip Discord-origin Chat message
* attachments
* long message handling
* reply context
* private/unreachable avatar fallback

## UI

Test:

* Discord display name shown instead of bridge account
* Discord avatar shown
* `DISCORD`/`via Discord` source badge
* no local user card for external identity
* two Discord users are not grouped as one author
* consecutive messages from same Discord user may group normally
* local Discourse messages render unchanged
* reply preview shows correct external Discord identity
* thread/message variants do not revert to bridge actor presentation
* deletion UI remains correct

## Security

Test:

* Discord `@admin` does not create a Discourse mention
* Discord `@all` does not create a Discourse channel-wide mention
* Discourse `@someone` does not ping Discord unless explicitly allowed
* secrets absent from serializers
* secrets absent from logs
* attachment SSRF attempts rejected
* oversized downloads aborted

# 49. Compatibility tests

Run plugin tests against the current supported Discourse branch.

Add CI similar to a normal modern Discourse plugin:

```text
lint
Ruby specs
frontend tests
plugin system tests where useful
```

Avoid pinning implementation to private undocumented internals where a public plugin extension API exists.

Where internal Chat APIs must be used, isolate access behind service classes so upgrades are easier.

# 50. Suggested plugin namespace

Use a clean namespace such as:

```ruby
DiscordChatBridge
```

Plugin name:

```text
discourse-discord-chat-bridge
```

Keep Discord API concerns separate from Discourse Chat concerns.

For example:

```text
DiscordChatBridge::Discord::Gateway
DiscordChatBridge::Discord::Client
DiscordChatBridge::Discord::WebhookClient

DiscordChatBridge::Inbound::CreateMessage
DiscordChatBridge::Inbound::UpdateMessage
DiscordChatBridge::Inbound::DeleteMessage

DiscordChatBridge::Outbound::CreateMessage
DiscordChatBridge::Outbound::UpdateMessage
DiscordChatBridge::Outbound::DeleteMessage
```

Do not create one enormous service object.

# 51. Suggested implementation phases

Implement in this order:

1. Plugin skeleton and settings
2. DB schema and channel mappings
3. Dedicated bridge actor
4. Discord REST/Webhook client
5. Discourse → Discord text create
6. Discourse → Discord edit/delete
7. Discord Gateway process
8. Discord → Discourse text create
9. Persistent message mapping and loop prevention
10. External Discord identity model
11. Discourse serializer/UI presentation
12. Correct message grouping
13. Discord → Discourse edit/delete
14. Replies
15. Attachments
16. Avatar caching
17. Admin UI
18. Gateway/process health
19. race/idempotency hardening
20. full test suite and documentation

Do not defer critical correctness issues such as loop prevention, idempotency, secret handling, or message grouping to "future work."

# 52. Acceptance scenario

This complete flow must work:

```text
Discord Alice:
"Hello"

        ↓

Discourse:
[alice avatar] Alice  DISCORD
Hello


Discourse Bob:
"Hi Alice"

        ↓

Discord:
[bob avatar] Bob
Hi Alice


Discord Alice edits:
"Hello everyone"

        ↓

same Discourse message becomes:
Hello everyone


Discourse Bob edits:
"Hi everyone"

        ↓

same Discord webhook message becomes:
Hi everyone


Discord Alice deletes her message

        ↓

mirrored Discourse message is trashed/deleted


Discourse Bob deletes his message

        ↓

mirrored Discord webhook message is deleted
```

No duplicate messages may appear because the bridge sees its own traffic.

# 53. Identity acceptance scenario

Given:

```text
Discord user ID: 123
display name: Alice
```

then later:

```text
Discord user ID: 123
display name: Alice Cooper
```

the system must recognize this as the same external identity.

Historical presentation behavior should be deliberately chosen and documented:

* either old messages retain the display name used at send time
* or all messages reflect the current external identity

Prefer storing a presentation snapshot on each message if that gives more accurate historical chat rendering.

The stable identity key remains Discord user ID in either case.

# 54. Message grouping acceptance scenario

This must render correctly:

```text
Alice [DISCORD]
A

Bob [DISCORD]
B

Alice [DISCORD]
C
D
```

Messages B and C must never disappear under grouping merely because every Discord-origin Chat message has the same technical `user_id`.

# 55. Explicit non-goals for version 1

Do not implement unless required for core functionality:

* cross-platform reaction identity synchronization
* typing indicators
* presence
* read receipts
* voice
* Discord role ↔ Discourse group synchronization
* automatic user account creation
* automatic channel creation
* full historical import
* arbitrary Discord bot command framework
* forum Topic/Post bridging
* Discord DM bridging

Focus on high-quality Chat channel bridging.

# 56. Documentation

Produce a complete README covering:

1. What the plugin does
2. Architecture
3. Supported features
4. Known limitations/asymmetries
5. Discord Developer Portal setup
6. Required Gateway intents
7. Required Discord permissions
8. Creating/configuring the Discord webhook
9. Installing the Discourse plugin
10. Starting the plugin Gateway process
11. Creating channel mappings
12. Security considerations
13. Backup implications
14. Upgrade procedure
15. Troubleshooting
16. Log locations
17. Health/status diagnostics
18. How to run tests

Include exact commands where possible.

# 57. Final engineering requirements

Before declaring the implementation finished:

* run the plugin test suite
* run Discourse plugin lint
* run frontend lint/tests
* inspect database indexes
* verify no plaintext credentials are exposed
* verify Gateway reconnect behavior
* verify restart behavior
* verify loop protection in a real bidirectional scenario
* verify create/edit/delete in both directions
* verify at least two different Discord identities render correctly
* verify Discord-origin users do not exist as Discourse `User` records
* verify mention safety
* verify attachments do not enable SSRF
* verify Discord and Discourse rate-limit behavior

# 58. Required final response from you

Do not stop after analysis.

First provide a concise implementation plan, then implement the plugin.

After implementation, report:

1. Architecture used
2. Files added/changed
3. Database schema
4. Gateway runtime model
5. Identity/presentation model
6. Channel mapping model
7. Create/edit/delete behavior in both directions
8. Reply behavior and any Discord API limitations
9. Attachment handling
10. Loop-prevention strategy
11. Idempotency/race strategy
12. Security model
13. Discord permissions and intents required
14. Admin configuration
15. Known limitations
16. Test results
17. Exact installation and startup instructions

Do not return pseudo-code as the final implementation.

Deliver working production-oriented code.
