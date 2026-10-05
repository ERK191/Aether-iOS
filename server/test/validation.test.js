"use strict";

import test from "node:test";
import assert from "node:assert/strict";
import { parseId, validateAvatar, validateCredentials, validateMessage } from "../validation.mjs";
import { canReceiveRealtimeEvent } from "../realtime.mjs";

test("valid credentials are trimmed without changing password whitespace", () => {
  assert.deepEqual(validateCredentials("  Aether_User  ", "  secure-pass "), {
    username: "Aether_User",
    password: "  secure-pass "
  });
});

test("rejects malformed usernames and short or oversized passwords", () => {
  assert.ok(validateCredentials("ab", "secure-pass").error);
  assert.ok(validateCredentials("contains spaces", "secure-pass").error);
  assert.ok(validateCredentials("valid_name", "short").error);
  assert.ok(validateCredentials("valid_name", "é".repeat(37)).error);
});

test("trims valid messages and enforces non-empty 2000-character limit", () => {
  assert.deepEqual(validateMessage(" hello "), { content: "hello" });
  assert.ok(validateMessage(" \n ").error);
  assert.ok(validateMessage("a".repeat(2001)).error);
  assert.equal([...validateMessage("é".repeat(2000)).content].length, 2000);
});

test("parses only bounded positive integer identifiers", () => {
  assert.equal(parseId("42"), 42);
  assert.equal(parseId("0"), null);
  assert.equal(parseId("-1"), null);
  assert.equal(parseId("1.2"), null);
  assert.equal(parseId("9007199254740992"), null);
});

test("accepts supported avatars, removal, and rejects invalid or oversized image data", () => {
  const images = [
    ["image/png", Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])],
    ["image/jpeg", Buffer.from([0xff, 0xd8, 0xff])],
    ["image/gif", Buffer.from("GIF89a")],
    ["image/webp", Buffer.from("RIFF0000WEBP")]
  ];
  for (const [mime, bytes] of images) {
    const avatar = `data:${mime};base64,${bytes.toString("base64")}`;
    assert.deepEqual(validateAvatar(avatar), { avatar });
  }
  assert.deepEqual(validateAvatar(null), { avatar: null });
  assert.ok(validateAvatar("https://example.com/avatar.png").error);
  assert.ok(validateAvatar("data:image/png;base64,YWJj").error);
  assert.ok(validateAvatar(`data:image/png;base64,${Buffer.alloc(1024 * 1024 + 1).toString("base64")}`).error);
});

test("realtime delivery preserves public channels and isolates server and direct-message scopes", () => {
  assert.equal(canReceiveRealtimeEvent({ scope: "public-channel" }, "42"), true);
  assert.equal(canReceiveRealtimeEvent({ scope: "server-channel", memberIds: ["42", "43"] }, "42"), true);
  assert.equal(canReceiveRealtimeEvent({ scope: "server-channel", memberIds: ["42", "43"] }, "44"), false);
  assert.equal(canReceiveRealtimeEvent({ scope: "server-channel", memberIds: [] }, "42"), false);
  assert.equal(canReceiveRealtimeEvent({ scope: "direct-message", recipientIds: ["42", "43"] }, "44"), false);
  assert.equal(canReceiveRealtimeEvent({ scope: "direct-message", recipientIds: ["42", "43"] }, "43"), true);
  assert.equal(canReceiveRealtimeEvent({ scope: "unknown" }, "42"), false);
});
