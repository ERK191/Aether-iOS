"use strict";

import test from "node:test";
import assert from "node:assert/strict";
import { parseId, validateCredentials, validateMessage } from "../validation.mjs";

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
