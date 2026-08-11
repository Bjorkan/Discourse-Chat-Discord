# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Single Discourse plugin: Ruby/Rails, PostgreSQL, Redis, Sidekiq, and Discourse's Ember/Glimmer admin UI.

## Users

Discourse administrators configure and operate the bridge. Community members converse in mapped Discord text channels and Discourse Chat channels without managing a second identity.

## Product Purpose

Mirror Chat conversations bidirectionally while preserving visible human identity, message lifecycle, replies, files, and searchability. Success means reliable create/edit/delete synchronization without loops, duplicate users, accidental mentions, or duplicate messages.

## Positioning

The bridge is one deployable Discourse plugin. Discord authors are first-class external identities attached to genuine Chat messages owned by one technical bot, never synthetic Discourse accounts.

## Operating Context

Administrators configure a Discord application, privileged Message Content intent, channel webhooks, and one-to-one channel mappings. A supervised plugin demon consumes Gateway events; Sidekiq performs synchronization.

## Capabilities and Constraints

The product supports directional mappings, identity snapshots, create/edit/delete, replies, attachments, mention safety, health diagnostics, and encrypted stored credentials. Reactions, presence, typing, DMs, forum posts, automatic channels, and history import are non-goals. Discord incoming webhooks do not support documented native message references, so Discourse replies use compact linked context.

## Product Principles

- Preserve identity without manufacturing accounts.
- Make synchronization idempotent and loop-safe at every boundary.
- Treat external content and credentials as hostile or sensitive by default.
- Keep operations observable, recoverable, and least-privileged.
- Inherit Discourse administration and Chat interaction conventions.

## Accessibility & Inclusion

The admin interface uses native Discourse controls, labels, keyboard focus behavior, semantic status text, and responsive layouts.
