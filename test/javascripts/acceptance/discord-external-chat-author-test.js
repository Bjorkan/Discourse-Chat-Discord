import { settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import initializer, {
  decorateExternalAuthor,
  initializeExternalAuthorPresentation,
  registerExternalAuthorDecorator,
} from "discourse/plugins/discourse-discord-chat-bridge/discourse/initializers/discord-external-chat-authors";

module("Discord Chat Bridge | external author presentation", function () {
  test("registers without cross-registry initializer dependencies", function (assert) {
    let registeredDecorator;
    const api = {
      decorateChatMessage(decorator) {
        registeredDecorator = decorator;
      },
    };

    assert.strictEqual(initializer.after, undefined);
    assert.strictEqual(initializer.before, undefined);
    assert.true(registerExternalAuthorDecorator(api));
    assert.strictEqual(registeredDecorator, decorateExternalAuthor);
    assert.false(registerExternalAuthorDecorator({}));
    assert.false(
      registerExternalAuthorDecorator({
        decorateChatMessage() {
          throw new Error("incompatible Chat API");
        },
      })
    );
    assert.false(
      initializeExternalAuthorPresentation(() => {
        throw new Error("plugin API unavailable");
      })
    );
  });

  test("shows the source badge and removes local user-card interactions", async function (assert) {
    const row = document.createElement("div");
    row.innerHTML = `
      <div class="chat-message">
        <div class="chat-message-avatar"><a class="chat-user-avatar__container" data-user-card="Alice"><img alt="" src="/discord-chat-bridge/avatar/123/48.png" /></a></div>
        <span role="button" data-user-card="Alice" class="group--discord-external clickable">Alice</span>
        <div class="chat-cooked">Hello</div>
      </div>`;
    document.querySelector("#qunit-fixture").append(row);

    decorateExternalAuthor(row.querySelector(".chat-cooked"));
    await settled();

    assert.strictEqual(
      row.querySelector(".discord-chat-bridge-source")?.textContent,
      "DISCORD"
    );
    assert.false(
      row
        .querySelector(".group--discord-external")
        ?.hasAttribute("data-user-card")
    );
    assert.strictEqual(row.querySelector(".chat-message-avatar a"), null);
    row.remove();
  });

  test("leaves local Discourse messages unchanged", async function (assert) {
    const row = document.createElement("div");
    row.innerHTML = `<div class="chat-message"><span data-user-card="bob">Bob</span><div class="chat-cooked">Hi</div></div>`;
    document.querySelector("#qunit-fixture").append(row);

    decorateExternalAuthor(row.querySelector(".chat-cooked"));
    await settled();

    assert.notStrictEqual(row.querySelector("[data-user-card='bob']"), null);
    assert.strictEqual(row.querySelector(".discord-chat-bridge-source"), null);
    row.remove();
  });

  test("makes an external reply-preview avatar noninteractive", async function (assert) {
    const row = document.createElement("div");
    row.innerHTML = `
      <div class="chat-message">
        <div class="chat-reply">
          <span class="chat-user-avatar">
            <a data-user-card="Alice"><img src="/discord-chat-bridge/avatar/123/24.png" /></a>
          </span>
        </div>
        <span data-user-card="bob">Bob</span>
        <div class="chat-cooked">Replying</div>
      </div>`;
    document.querySelector("#qunit-fixture").append(row);

    decorateExternalAuthor(row.querySelector(".chat-cooked"));
    await settled();

    assert.strictEqual(row.querySelector(".chat-reply [data-user-card]"), null);
    assert.notStrictEqual(row.querySelector(".chat-reply img"), null);
    row.remove();
  });
});
