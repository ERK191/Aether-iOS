"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const target = path.resolve(process.cwd(), ".env.aether");
const secret = crypto.randomBytes(48).toString("base64url");
try {
  const descriptor = fs.openSync(target, "wx", 0o600);
  try {
    fs.writeFileSync(descriptor, `AETHER_JWT_SECRET=${secret}\n`, { encoding: "utf8" });
  } finally {
    fs.closeSync(descriptor);
  }
  console.log("Created private .env.aether. It is ignored by Git; do not share or commit it.");
} catch (error) {
  if (error.code === "EEXIST") {
    console.error(".env.aether already exists; leaving your existing signing key unchanged.");
    process.exitCode = 1;
    return;
  }
  throw error;
}
