import { defineConfig } from "@neon/config/v1";

const jwtSecret = process.env.AETHER_JWT_SECRET;
if (!jwtSecret || Buffer.byteLength(jwtSecret, "utf8") < 32) {
  throw new Error("Create .env.aether with `npm run setup:secret` before deploying.");
}

export default defineConfig({
  functions: {
    aether: {
      name: "Aether Chat API",
      source: "./functions/aether.ts",
      env: {
        AETHER_JWT_SECRET: jwtSecret
      }
    }
  }
});
