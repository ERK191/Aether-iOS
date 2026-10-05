# Aether

A Discord-inspired native group chat for iOS 13 and newer, with your seashell artwork as its icon. Neon hosts both Aether's PostgreSQL database and its serverless API function; no separate Render or Supabase account is required.

## What's included

- iOS 13+ Swift/UIKit app with sign-up, login, channels, message history, secure Keychain sessions, and live chat.
- Neon Function API for password-hashed accounts, authenticated endpoints, rate limits, PostgreSQL-backed chat, and cross-isolate live updates.
- Existing Neon project link for project `old-bonus-14476007`, branch `production`.
- GitHub Actions workflow for API validation and unsigned TrollStore package builds on macOS 26.

## Current setup status

- This local folder is linked to your Neon `production` branch, in AWS US East 2 (Ohio), a supported Neon Functions region.
- The Aether backend is deployed as a Neon Function, and its health endpoint has been verified.
- Your Neon database connection string is injected by Neon into the function at runtime; it is not in the app or repository.
- The iOS app is configured with the public function URL. Account and chat tables are initialized when the app first uses the API.

## Deploy Aether's API to your Neon project

From PowerShell, in this project folder:

1. Create a local, random signing secret. It is saved to `.env.aether`, ignored by Git, and not printed:

   ```powershell
   npm run setup:secret
   ```

   Keep `.env.aether` private. Do not paste its contents into chat, upload it, or commit it.

2. Preview the Neon change. This is a dry run; it does not deploy:

   ```powershell
   npx neon@latest config plan --env .env.aether
   ```

   The plan should show the Aether Function on the `production` branch. If it says anything unexpected about deleting or changing your database, stop instead of deploying.

3. To publish or update the API after changing its source, deploy it:

   ```powershell
   npx neon@latest deploy --env .env.aether --no-env-pull
   ```

   This publishes the function to Neon. It does not change your GitHub build.

4. To look up the public HTTPS invocation URL:

   ```powershell
   npx neon@latest functions get aether
   ```

   The current URL is already configured in `Aether/AppConfiguration.swift`. If you deploy to a different branch, update that value to the new invocation URL. Treat the URL as public; it is not a secret.

5. Upload/commit the updated project to GitHub. Run **Actions → Build Aether for TrollStore** and download the `Aether-TrollStore` artifact when the run succeeds. Extract `Aether.tipa`, move it to the iPhone, and install it with TrollStore.

Neon Functions run on Neon infrastructure and can scale down when idle. Free-plan usage limits and product terms can change; free hosting cannot guarantee uninterrupted availability or zero data loss. Export important database data regularly.

## Chat

The API creates the account, channel, message, and rate-limit tables when it is first used, then seeds `#general`, `#gaming`, and `#introductions`. Neon Functions use the same Postgres database shown in your Neon Console. Live-message polling runs only while a WebSocket connection is active and stops when the isolate has no connected chat clients.

Usernames are 3–24 letters, numbers, or underscores. Passwords are bcrypt-hashed before storage and must be at least 8 characters (72 UTF-8 bytes maximum). Message text is limited to 2,000 characters.

## Development checks

Run `npm test` for the validation suite. `neon dev` runs the declared function locally using the linked branch; `npx neon@latest config plan --env .env.aether` previews the cloud deployment. Building the iOS app itself requires Xcode, so the included GitHub Actions macOS runner builds it for Windows users.
