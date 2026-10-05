# Aether

A Discord-inspired native group chat for iOS 13 and newer, with your seashell artwork as its icon. Neon hosts both Aether's PostgreSQL database and its serverless API function; no separate Render or Supabase account is required.

## What's included

- iOS 13+ Swift/UIKit app with sign-up, login, channels, message history, secure Keychain sessions, and live chat.
- Owner tools for the reserved `DevErick` account: global account bans, server-member kicks, and test-account creation.
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

## Extended API

All `/api` routes below require `Authorization: Bearer <token>` unless they are the existing register/login routes. JSON errors use `{ "error": "..." }`. IDs in the new endpoints are decimal strings.

WebSocket `/ws` also requires the bearer token in the `Authorization` header. Its existing `ready` event and shared public/community-channel `message` events are delivered to all authenticated connected users. Server-channel events are delivered only to users who are server members when the event is polled; joining is required to list channels, read/post server-channel messages, and receive their WebSocket events. The WebSocket feed reads only channel messages; direct messages are REST-only and are never broadcast. Direct-conversation read/post routes require authentication and verify the caller is one of that conversation's two participants.

- `GET /api/users?query=<prefix>` searches usernames (2–24 characters, up to 50 results): `{ "users": [{ "id": "…", "username": "…", "avatar": null }] }`.
- `GET /api/friends` returns `{ "friends": [{ "user": { "id": "…", "username": "…", "avatar": null }, "since": "…" }] }`. Create a request with `POST /api/friends/requests` and `{ "user_id": "…" }`, returning `{ "request": { "id", "requester_id", "recipient_id", "status": "pending", "created_at", "updated_at" } }`. Inspect incoming/outgoing/all request states with `GET /api/friends/requests`, which returns `{ "requests": [{ "id", "status", "direction": "incoming|outgoing", "user", "created_at" }] }`. Accept or reject with `POST /api/friends/requests/:requestId/accept` or `/reject`; each returns `{ "request": { "id", "status", "requester_id", "recipient_id", "created_at", "updated_at" } }`. Remove an accepted friend with `DELETE /api/friends/:userId`, returning `{ "removed": true }`.
- `GET /api/conversations` returns `{ "conversations": [{ "id", "user": { "id", "username", "avatar" }, "created_at", "last_message": null|{ "id", "user_id", "content", "created_at" } }] }`. Open or retrieve a persistent one-to-one conversation with `POST /api/conversations` and `{ "user_id": "…" }`, returning `{ "conversation": { "id", "user_id", "created_at" } }`. Read/post messages at `/api/conversations/:conversationId/messages` using `{ "content": "…" }` and `limit`/`before` pagination; responses use `{ "messages": [...] }` or `{ "message": {...} }`.
- `GET /api/servers` lists `{ "servers": [{ "id", "name", "description", "owner_id", "created_at", "member_count", "is_member" }] }`. Create one with `POST /api/servers` and `{ "name": "…", "description": "…" }` (returns `{ "server": {...}, "channels": [{ "id", "server_id", "name", "description", "position" }] }` and creates a `general` channel); inspect with `GET /api/servers/:serverId` (`{ "server": {...} }`), join with `POST /api/servers/:serverId/join` (`{ "server_id": "…", "joined": true }`), and leave with `DELETE /api/servers/:serverId/membership` (`{ "server_id": "…", "left": true }`). The owner can delete the server with `DELETE /api/servers/:serverId`. `GET /api/servers/:serverId/channels` returns `{ "channels": [...] }` only to members. Channel message routes use the existing format and enforce membership for server channels; the legacy `/api/channels` remains scoped to the seeded community channels.
- `PUT /api/me/avatar` accepts `{ "avatar": "data:image/png;base64,…" }`; PNG, JPEG, GIF, and WebP are accepted up to 1 MiB decoded. Set `avatar` to `null` to remove it. The base64 data is stored in Postgres and returned as `user.avatar`; no external image service is used.
- `DELETE /api/me` returns `{ "deleted": true }`. Foreign-key cascades remove the account's messages, friendships/requests, direct conversations/messages, memberships, rate-limit row, and owned servers and their channels/messages.
- Owner-only moderation endpoints are available only to the existing, reserved `DevErick` account. `GET /api/owner/users?query=<prefix>` searches accounts; `POST /api/owner/users/:userId/ban` accepts an optional `{ "reason": "..." }`, while `DELETE` on that route restores access. A ban blocks login and authenticated requests and closes active chat sockets. `POST /api/owner/test-accounts` accepts `{ "username": "...", "password": "..." }` and creates an ordinary, non-owner account marked for testing. `GET /api/owner/servers/:serverId/members` lists members; `DELETE /api/owner/servers/:serverId/members/:userId` kicks a member without allowing server owners to be kicked.
- The `DevErick` username is reserved from public registration and its account cannot be deleted or banned, so owner permissions cannot be claimed by registering that handle later. Existing databases are upgraded automatically when the API starts.

Messages remain limited to 2,000 characters and 100 per page. Existing auth and community-channel response formats are retained, with `avatar` added to user objects returned by `/api/me`, register, and login.

## Development checks

Run `npm test` for the validation suite. `neon dev` runs the declared function locally using the linked branch; `npx neon@latest config plan --env .env.aether` previews the cloud deployment. Building the iOS app itself requires Xcode, so the included GitHub Actions macOS runner builds it for Windows users.
