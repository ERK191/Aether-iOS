import { attachDatabasePool } from "@neon/functions";
import { upgradeWebSocket } from "@neon/functions/hono";
import { Hono, type MiddlewareHandler } from "hono";
import bcrypt from "bcryptjs";
import jwt, { type JwtPayload } from "jsonwebtoken";
import { Client, Pool, type PoolClient } from "pg";
import {
  parseId,
  validateAvatar,
  validateCredentials,
  validateMessage,
  type ValidAvatar,
  type ValidCredentials
} from "../server/validation.mjs";
import { canReceiveRealtimeEvent, type RealtimeAudience } from "../server/realtime.mjs";

type PublicUser = { id: string; username: string; avatar?: string | null; is_owner: boolean };
type AuthUser = { id: string; username: string; isOwner: boolean };
type ValidChatMessage = { content: string; image_data?: string };
type Variables = { user: AuthUser };
type AppEnvironment = { Variables: Variables };
type SocketEvent = {
  type: "ready" | "message";
  message?: Record<string, unknown>;
};

const jwtSecret = process.env.AETHER_JWT_SECRET;
if (!jwtSecret || Buffer.byteLength(jwtSecret, "utf8") < 32) {
  throw new Error("AETHER_JWT_SECRET must be at least 32 bytes.");
}
if (!process.env.DATABASE_URL) {
  throw new Error("The Neon Postgres service must be enabled for this branch.");
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 3,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000
});
attachDatabasePool(pool);

const sockets = new Map<WebSocket, string>();
let schemaPromise: Promise<void> | null = null;
let feedPromise: Promise<void> | null = null;
let feedTimer: ReturnType<typeof setInterval> | null = null;
let feedCursor = "0";
let feedPolling = false;

const app = new Hono<AppEnvironment>();

function jsonError(message: string, status: 400 | 401 | 403 | 404 | 409 | 429 | 500 | 503) {
  return Response.json({ error: message }, { status });
}

function credentials(value: unknown): ValidCredentials | null {
  const source = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const result = validateCredentials(source.username, source.password);
  return "error" in result ? null : result;
}

function parseSessionId(value: unknown): string | null {
  if (typeof value !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    return null;
  }
  return value.toLowerCase();
}

function validatedMessage(value: unknown): ValidChatMessage | null {
  const source = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const result = validateMessage(source.content, source.image_data);
  return "error" in result ? null : result;
}

function avatarDetails(value: unknown): ValidAvatar | null {
  const source = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const result = validateAvatar(source.avatar);
  return "error" in result ? null : result;
}

function publicUser(row: {
  id: string | number;
  username: string;
  avatar_data?: string | null;
  is_owner?: boolean;
}): PublicUser {
  return {
    id: String(row.id),
    username: row.username,
    avatar: row.avatar_data ?? null,
    is_owner: row.is_owner ?? false
  };
}

function signToken(user: PublicUser): string {
  return jwt.sign({ username: user.username }, jwtSecret!, {
    subject: user.id,
    issuer: "aether",
    expiresIn: "30d"
  });
}

function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer ([A-Za-z0-9._-]+)$/.exec(header);
  return match ? match[1] : null;
}

async function ensureSchema(): Promise<void> {
  if (!schemaPromise) {
    schemaPromise = pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id BIGSERIAL PRIMARY KEY,
        username VARCHAR(24) NOT NULL,
        username_key VARCHAR(24) NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_data TEXT;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN NOT NULL DEFAULT FALSE;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS ban_reason TEXT;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS is_test_account BOOLEAN NOT NULL DEFAULT FALSE;
      CREATE TABLE IF NOT EXISTS servers (
        id BIGSERIAL PRIMARY KEY,
        name VARCHAR(64) NOT NULL,
        description VARCHAR(240) NOT NULL DEFAULT '',
        owner_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS servers_name_id_idx ON servers (lower(name), id);
      CREATE TABLE IF NOT EXISTS channels (
        id BIGSERIAL PRIMARY KEY,
        name VARCHAR(32) NOT NULL UNIQUE,
        description VARCHAR(160) NOT NULL,
        position INTEGER NOT NULL,
        server_id BIGINT REFERENCES servers(id) ON DELETE CASCADE
      );
      ALTER TABLE channels ADD COLUMN IF NOT EXISTS server_id BIGINT REFERENCES servers(id) ON DELETE CASCADE;
      ALTER TABLE channels DROP CONSTRAINT IF EXISTS channels_name_key;
      CREATE UNIQUE INDEX IF NOT EXISTS channels_server_name_uidx
        ON channels ((COALESCE(server_id, 0)), name);
      CREATE TABLE IF NOT EXISTS messages (
        id BIGSERIAL PRIMARY KEY,
        channel_id BIGINT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        content VARCHAR(2000) NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      ALTER TABLE messages ADD COLUMN IF NOT EXISTS image_data TEXT;
      CREATE INDEX IF NOT EXISTS messages_channel_id_id_idx ON messages (channel_id, id DESC);
      CREATE TABLE IF NOT EXISTS auth_rate_limits (
        username_key VARCHAR(24) PRIMARY KEY,
        window_started_at TIMESTAMPTZ NOT NULL,
        attempts INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS message_rate_limits (
        user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        window_started_at TIMESTAMPTZ NOT NULL,
        attempts INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS server_memberships (
        server_id BIGINT NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role VARCHAR(16) NOT NULL DEFAULT 'member',
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (server_id, user_id)
      );
      CREATE INDEX IF NOT EXISTS server_memberships_user_id_idx ON server_memberships (user_id, server_id);
      CREATE TABLE IF NOT EXISTS friend_requests (
        id BIGSERIAL PRIMARY KEY,
        requester_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        recipient_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        status VARCHAR(16) NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'accepted', 'rejected')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        CHECK (requester_id <> recipient_id),
        UNIQUE (requester_id, recipient_id)
      );
      CREATE INDEX IF NOT EXISTS friend_requests_recipient_status_idx
        ON friend_requests (recipient_id, status, created_at DESC);
      CREATE UNIQUE INDEX IF NOT EXISTS friend_requests_pair_uidx
        ON friend_requests (LEAST(requester_id, recipient_id), GREATEST(requester_id, recipient_id));
      CREATE TABLE IF NOT EXISTS direct_conversations (
        id BIGSERIAL PRIMARY KEY,
        participant_low_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        participant_high_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        CHECK (participant_low_id < participant_high_id),
        UNIQUE (participant_low_id, participant_high_id)
      );
      CREATE TABLE IF NOT EXISTS direct_messages (
        id BIGSERIAL PRIMARY KEY,
        conversation_id BIGINT NOT NULL REFERENCES direct_conversations(id) ON DELETE CASCADE,
        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        content VARCHAR(2000) NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS image_data TEXT;
      CREATE INDEX IF NOT EXISTS direct_messages_conversation_id_id_idx
        ON direct_messages (conversation_id, id DESC);
      CREATE TABLE IF NOT EXISTS read_state (
        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        scope VARCHAR(8) NOT NULL CHECK (scope IN ('channel', 'direct')),
        room_id BIGINT NOT NULL,
        last_read_message_id BIGINT NOT NULL,
        PRIMARY KEY (user_id, scope, room_id)
      );
      CREATE TABLE IF NOT EXISTS presence_sessions (
        session_id UUID PRIMARY KEY,
        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS presence_sessions_user_last_seen_idx
        ON presence_sessions (user_id, last_seen_at DESC);
      INSERT INTO channels (name, description, position) VALUES
        ('general', 'Chat with everyone in the community.', 1),
        ('gaming', 'Talk games, teams, and what you are playing.', 2),
        ('introductions', 'Say hello and meet the community.', 3)
      ON CONFLICT DO NOTHING;
    `).then(() => undefined).catch((error: unknown) => {
      schemaPromise = null;
      throw error;
    });
  }
  await schemaPromise;
}

async function allowRate(
  table: "auth_rate_limits" | "message_rate_limits",
  key: string,
  limit: number
): Promise<boolean> {
  const keyColumn = table === "auth_rate_limits" ? "username_key" : "user_id";
  const result = await pool.query<{ attempts: number }>(
    `INSERT INTO ${table} (${keyColumn}, window_started_at, attempts)
     VALUES ($1, clock_timestamp(), 1)
     ON CONFLICT (${keyColumn}) DO UPDATE SET
       attempts = CASE
         WHEN ${table}.window_started_at <= clock_timestamp() - interval '1 minute' THEN 1
         ELSE ${table}.attempts + 1
       END,
       window_started_at = CASE
         WHEN ${table}.window_started_at <= clock_timestamp() - interval '1 minute' THEN clock_timestamp()
         ELSE ${table}.window_started_at
       END
     RETURNING attempts`,
    [key]
  );
  return result.rows[0].attempts <= limit;
}

const requireAuth: MiddlewareHandler<AppEnvironment> = async (context, next) => {
  const token = bearerToken(context.req.header("authorization"));
  if (!token) return context.json({ error: "Sign in to continue." }, 401);
  try {
    const payload = jwt.verify(token, jwtSecret!, { issuer: "aether" }) as JwtPayload & { username?: string };
    if (typeof payload.sub !== "string" || typeof payload.username !== "string") {
      return context.json({ error: "Your session is invalid. Sign in again." }, 401);
    }
    await ensureSchema();
    const account = await pool.query(
      `SELECT id, username, username_key, is_banned
       FROM users WHERE id = $1`,
      [payload.sub]
    );
    if (!account.rows[0]) return context.json({ error: "Account no longer exists." }, 401);
    if (account.rows[0].is_banned) return context.json({ error: "This account has been banned." }, 403);
    context.set("user", {
      id: payload.sub,
      username: account.rows[0].username,
      isOwner: account.rows[0].username_key === "deverick"
    });
    await next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError || error instanceof jwt.JsonWebTokenError) {
      return context.json({ error: "Your session expired. Sign in again." }, 401);
    }
    throw error;
  }
};

const requireOwner: MiddlewareHandler<AppEnvironment> = async (context, next) => {
  if (!context.get("user").isOwner) return jsonError("Only the Aether owner can use this feature.", 403);
  await next();
};

function closeUserSockets(userId: string): void {
  for (const [socket, connectedUserId] of sockets) {
    if (connectedUserId !== userId) continue;
    try {
      socket.close(1008, "Account banned");
    } catch (error) {
      console.error("Could not close banned user's chat connection:", error);
    }
    releaseMessageFeed(socket);
  }
}

function broadcast(event: SocketEvent, audience: RealtimeAudience): void {
  const payload = JSON.stringify(event);
  for (const [socket, userId] of sockets) {
    if (!canReceiveRealtimeEvent(audience, userId)) continue;
    if (socket.readyState === WebSocket.OPEN) {
      try {
        socket.send(payload);
      } catch (error) {
        console.error("Could not send chat event:", error);
        socket.close(1011, "Message delivery failed");
      }
    }
  }
}

async function pollMessages(): Promise<void> {
  if (feedPolling || sockets.size === 0) return;
  feedPolling = true;
  try {
    const connectedUserIds = [...new Set(sockets.values())];
    const bannedUsers = await pool.query(
      "SELECT id FROM users WHERE is_banned = TRUE AND id = ANY($1::bigint[])",
      [connectedUserIds]
    );
    for (const row of bannedUsers.rows) closeUserSockets(String(row.id));
    if (sockets.size === 0) return;

    const result = await pool.query(
      `SELECT m.id, m.channel_id, m.user_id, u.username, u.avatar_data AS avatar,
              m.content, m.image_data, m.created_at,
              c.server_id, recipients.member_ids
       FROM messages m
       JOIN users u ON u.id = m.user_id
       JOIN channels c ON c.id = m.channel_id
       LEFT JOIN LATERAL (
         SELECT array_agg(sm.user_id::text) AS member_ids
         FROM server_memberships sm
         WHERE sm.server_id = c.server_id
       ) recipients ON c.server_id IS NOT NULL
       WHERE m.id > $1::bigint
       ORDER BY m.id ASC
       LIMIT 100`,
      [feedCursor]
    );
    for (const row of result.rows) {
      feedCursor = String(row.id);
      const { member_ids: memberIds, server_id: serverId, ...message } = row;
      broadcast(
        { type: "message", message },
        serverId === null
          ? { scope: "public-channel" }
          : { scope: "server-channel", memberIds: memberIds ?? [] }
      );
    }
  } catch (error) {
    console.error("Aether realtime polling failed:", error);
  } finally {
    feedPolling = false;
  }
}

async function startMessageFeed(): Promise<void> {
  if (!feedPromise) {
    feedPromise = pool.query("SELECT COALESCE(MAX(id), 0)::text AS id FROM messages")
      .then((result) => {
        feedCursor = String(result.rows[0].id);
      })
      .catch((error: unknown) => {
        feedPromise = null;
        throw error;
      });
  }
  await feedPromise;
  if (!feedTimer) {
    feedTimer = setInterval(() => {
      if (sockets.size === 0) {
        if (feedTimer) clearInterval(feedTimer);
        feedTimer = null;
        feedPromise = null;
        return;
      }
      void pollMessages();
    }, 1000);
    feedTimer.unref?.();
  }
}

function releaseMessageFeed(socket: WebSocket): void {
  sockets.delete(socket);
  if (sockets.size === 0 && feedTimer) {
    clearInterval(feedTimer);
    feedTimer = null;
    feedPromise = null;
  }
}

app.get("/health", (context) => context.json({ status: "ok", service: "aether" }));

app.post("/api/auth/register", async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON to create an account.", 400);
  }
  const details = credentials(body);
  if (!details) {
    return jsonError("Enter a valid username (3–24 letters, numbers, or underscores) and a password of 8–72 UTF-8 bytes.", 400);
  }
  if (details.username.toLowerCase() === "deverick") {
    return jsonError("The Aether owner username is reserved.", 409);
  }
  if (!(await allowRate("auth_rate_limits", details.username.toLowerCase(), 5))) {
    return jsonError("Too many account attempts. Try again in a minute.", 429);
  }
  try {
    const passwordHash = await bcrypt.hash(details.password, 12);
    const result = await pool.query(
      `INSERT INTO users (username, username_key, password_hash)
       VALUES ($1, $2, $3)
       RETURNING id, username`,
      [details.username, details.username.toLowerCase(), passwordHash]
    );
    const user = publicUser(result.rows[0]);
    return context.json({ token: signToken(user), user }, 201);
  } catch (error) {
    if (typeof error === "object" && error !== null && "code" in error && error.code === "23505") {
      return jsonError("That username is already taken.", 409);
    }
    throw error;
  }
});

app.post("/api/auth/login", async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON to sign in.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const username = typeof source.username === "string" ? source.username.trim() : "";
  const password = typeof source.password === "string" ? source.password : "";
  const details = credentials({ username, password });
  if (!details) return jsonError("Username or password is incorrect.", 401);
  if (!(await allowRate("auth_rate_limits", details.username.toLowerCase(), 5))) {
    return jsonError("Too many account attempts. Try again in a minute.", 429);
  }
  const result = await pool.query(
    "SELECT id, username, password_hash, username_key, is_banned FROM users WHERE username_key = $1",
    [details.username.toLowerCase()]
  );
  const row = result.rows[0];
  const matches = row ? await bcrypt.compare(details.password, row.password_hash) : false;
  if (!matches) return jsonError("Username or password is incorrect.", 401);
  if (row.is_banned) return jsonError("This account has been banned.", 403);
  row.is_owner = row.username_key === "deverick";
  const user = publicUser(row);
  return context.json({ token: signToken(user), user });
});

app.get("/api/me", requireAuth, async (context) => {
  await ensureSchema();
  const currentUser = context.get("user");
  const result = await pool.query(
    "SELECT id, username, avatar_data, username_key = 'deverick' AS is_owner FROM users WHERE id = $1",
    [currentUser.id]
  );
  if (!result.rows[0]) return jsonError("Account no longer exists.", 401);
  return context.json({ user: publicUser(result.rows[0]) });
});

app.put("/api/me/avatar", requireAuth, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with an avatar data URL.", 400);
  }
  const avatar = avatarDetails(body);
  if (!avatar) return jsonError("Avatar must be a PNG, JPEG, GIF, or WebP data URL no larger than 1 MiB.", 400);
  const user = context.get("user");
  const result = await pool.query(
    `UPDATE users SET avatar_data = $2 WHERE id = $1
     RETURNING id, username, avatar_data, username_key = 'deverick' AS is_owner`,
    [user.id, avatar.avatar]
  );
  if (!result.rows[0]) return jsonError("Account no longer exists.", 401);
  return context.json({ user: publicUser(result.rows[0]) });
});

app.delete("/api/me", requireAuth, async (context) => {
  await ensureSchema();
  const user = context.get("user");
  if (user.isOwner) return jsonError("The Aether owner account cannot be deleted.", 403);
  const result = await pool.query(
    `WITH target AS (SELECT username_key FROM users WHERE id = $1),
     removed_limits AS (
       DELETE FROM auth_rate_limits USING target
       WHERE auth_rate_limits.username_key = target.username_key
     )
     DELETE FROM users WHERE id = $1 RETURNING id`,
    [user.id]
  );
  if (!result.rows[0]) return jsonError("Account no longer exists.", 401);
  return context.json({ deleted: true });
});

app.get("/api/owner/users", requireAuth, requireOwner, async (context) => {
  await ensureSchema();
  const query = (context.req.query("query") ?? "").trim();
  if ([...query].length < 2 || [...query].length > 24) {
    return jsonError("User search must contain 2–24 characters.", 400);
  }
  const owner = context.get("user");
  const result = await pool.query(
    `SELECT id, username, is_banned, is_test_account
     FROM users
     WHERE id <> $1 AND username_key LIKE $2
     ORDER BY username_key LIMIT 50`,
    [owner.id, `${query.toLowerCase().replace(/[\\%_]/g, "\\$&")}%`]
  );
  return context.json({
    users: result.rows.map((row) => ({
      id: String(row.id),
      username: row.username,
      is_banned: row.is_banned,
      is_test_account: row.is_test_account
    }))
  });
});

app.post("/api/owner/users/:userId/ban", requireAuth, requireOwner, async (context) => {
  await ensureSchema();
  const targetId = parseId(context.req.param("userId"));
  if (targetId === null) return jsonError("Invalid user.", 400);
  let body: unknown = {};
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with an optional ban reason.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const reason = typeof source.reason === "string" ? source.reason.trim() : "";
  if ([...reason].length > 200) return jsonError("Ban reasons must be at most 200 characters.", 400);
  const owner = context.get("user");
  const result = await pool.query(
    `UPDATE users SET is_banned = TRUE, ban_reason = $3
     WHERE id = $1 AND id <> $2 AND username_key <> 'deverick'
     RETURNING id, username, is_banned, is_test_account`,
    [targetId, owner.id, reason || null]
  );
  if (!result.rows[0]) return jsonError("User not found or the owner account cannot be banned.", 404);
  closeUserSockets(String(result.rows[0].id));
  const row = result.rows[0];
  return context.json({
    user: {
      id: String(row.id),
      username: row.username,
      is_banned: row.is_banned,
      is_test_account: row.is_test_account
    }
  });
});

app.delete("/api/owner/users/:userId/ban", requireAuth, requireOwner, async (context) => {
  await ensureSchema();
  const targetId = parseId(context.req.param("userId"));
  if (targetId === null) return jsonError("Invalid user.", 400);
  const owner = context.get("user");
  const result = await pool.query(
    `UPDATE users SET is_banned = FALSE, ban_reason = NULL
     WHERE id = $1 AND id <> $2 AND username_key <> 'deverick'
     RETURNING id, username, is_banned, is_test_account`,
    [targetId, owner.id]
  );
  if (!result.rows[0]) return jsonError("User not found or the owner account cannot be changed.", 404);
  const row = result.rows[0];
  return context.json({
    user: {
      id: String(row.id),
      username: row.username,
      is_banned: row.is_banned,
      is_test_account: row.is_test_account
    }
  });
});

app.post("/api/owner/test-accounts", requireAuth, requireOwner, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with a username and password.", 400);
  }
  const details = credentials(body);
  if (!details) {
    return jsonError("Enter a valid username (3–24 letters, numbers, or underscores) and a password of 8–72 UTF-8 bytes.", 400);
  }
  if (details.username.toLowerCase() === "deverick") {
    return jsonError("The Aether owner username is reserved.", 409);
  }
  if (!(await allowRate("auth_rate_limits", details.username.toLowerCase(), 5))) {
    return jsonError("Too many account attempts. Try again in a minute.", 429);
  }
  try {
    const passwordHash = await bcrypt.hash(details.password, 12);
    const result = await pool.query(
      `INSERT INTO users (username, username_key, password_hash, is_test_account)
       VALUES ($1, $2, $3, TRUE)
       RETURNING id, username, is_banned, is_test_account`,
      [details.username, details.username.toLowerCase(), passwordHash]
    );
    const row = result.rows[0];
    return context.json({
      user: {
        id: String(row.id),
        username: row.username,
        is_banned: row.is_banned,
        is_test_account: row.is_test_account
      }
    }, 201);
  } catch (error) {
    if (typeof error === "object" && error !== null && "code" in error && error.code === "23505") {
      return jsonError("That username is already taken.", 409);
    }
    throw error;
  }
});

app.get("/api/owner/servers/:serverId/members", requireAuth, requireOwner, async (context) => {
  await ensureSchema();
  const serverId = parseId(context.req.param("serverId"));
  if (serverId === null) return jsonError("Invalid server.", 400);
  const server = await pool.query("SELECT id FROM servers WHERE id = $1", [serverId]);
  if (!server.rows[0]) return jsonError("Server not found.", 404);
  const result = await pool.query(
    `SELECT u.id, u.username, u.avatar_data, sm.role, sm.created_at
     FROM server_memberships sm
     JOIN users u ON u.id = sm.user_id
     WHERE sm.server_id = $1
     ORDER BY CASE WHEN sm.role = 'owner' THEN 0 ELSE 1 END, u.username_key`,
    [serverId]
  );
  return context.json({
    members: result.rows.map((row) => ({
      user: publicUser(row),
      role: row.role,
      joined_at: row.created_at
    }))
  });
});

app.delete("/api/owner/servers/:serverId/members/:userId", requireAuth, requireOwner, async (context) => {
  await ensureSchema();
  const serverId = parseId(context.req.param("serverId"));
  const targetId = parseId(context.req.param("userId"));
  if (serverId === null || targetId === null) return jsonError("Invalid server or user.", 400);
  const result = await pool.query(
    `DELETE FROM server_memberships sm
     USING servers s
     WHERE sm.server_id = s.id AND sm.server_id = $1 AND sm.user_id = $2
       AND sm.role <> 'owner'
     RETURNING sm.user_id`,
    [serverId, targetId]
  );
  if (!result.rows[0]) return jsonError("Member not found or server owners cannot be kicked.", 404);
  return context.json({ kicked: true, user_id: String(result.rows[0].user_id) });
});

app.get("/api/users", requireAuth, async (context) => {
  await ensureSchema();
  const query = (context.req.query("query") ?? "").trim();
  if ([...query].length < 2 || [...query].length > 24) {
    return jsonError("User search must contain 2–24 characters.", 400);
  }
  const user = context.get("user");
  const result = await pool.query(
    `SELECT id, username, avatar_data FROM users
     WHERE id <> $1 AND username_key LIKE $2
     ORDER BY username_key LIMIT 50`,
    [user.id, `${query.toLowerCase().replace(/[\\%_]/g, "\\$&")}%`]
  );
  return context.json({ users: result.rows.map(publicUser) });
});

app.get("/api/friends", requireAuth, async (context) => {
  await ensureSchema();
  const user = context.get("user");
  const result = await pool.query(
    `SELECT u.id, u.username, u.avatar_data, fr.updated_at AS since
     FROM friend_requests fr
     JOIN users u ON u.id = CASE WHEN fr.requester_id = $1 THEN fr.recipient_id ELSE fr.requester_id END
     WHERE fr.status = 'accepted' AND (fr.requester_id = $1 OR fr.recipient_id = $1)
     ORDER BY u.username_key`,
    [user.id]
  );
  return context.json({
    friends: result.rows.map((row) => ({ user: publicUser(row), since: row.since }))
  });
});

app.get("/api/friends/requests", requireAuth, async (context) => {
  await ensureSchema();
  const user = context.get("user");
  const result = await pool.query(
    `SELECT fr.id, fr.status, fr.created_at,
            fr.requester_id, fr.recipient_id,
            requester.username AS requester_username, requester.avatar_data AS requester_avatar,
            recipient.username AS recipient_username, recipient.avatar_data AS recipient_avatar
     FROM friend_requests fr
     JOIN users requester ON requester.id = fr.requester_id
     JOIN users recipient ON recipient.id = fr.recipient_id
     WHERE fr.requester_id = $1 OR fr.recipient_id = $1
     ORDER BY fr.created_at DESC`,
    [user.id]
  );
  return context.json({
    requests: result.rows.map((row) => {
      const incoming = String(row.recipient_id) === user.id;
      const other = incoming
        ? { id: String(row.requester_id), username: row.requester_username, avatar_data: row.requester_avatar }
        : { id: String(row.recipient_id), username: row.recipient_username, avatar_data: row.recipient_avatar };
      return {
        id: String(row.id),
        status: row.status,
        direction: incoming ? "incoming" : "outgoing",
        user: publicUser(other),
        created_at: row.created_at
      };
    })
  });
});

app.post("/api/friends/requests", requireAuth, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with user_id.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const targetId = typeof source.user_id === "string" ? parseId(source.user_id) : null;
  const user = context.get("user");
  if (targetId === null || String(targetId) === user.id) return jsonError("Choose another valid user.", 400);
  const target = await pool.query("SELECT id FROM users WHERE id = $1", [targetId]);
  if (!target.rows[0]) return jsonError("User not found.", 404);

  const existing = await pool.query(
    `SELECT id, status FROM friend_requests
     WHERE (requester_id = $1 AND recipient_id = $2)
        OR (requester_id = $2 AND recipient_id = $1)
     LIMIT 1`,
    [user.id, targetId]
  );
  if (existing.rows[0]?.status === "accepted") return jsonError("You are already friends.", 409);
  if (existing.rows[0]?.status === "pending") return jsonError("A friend request already exists.", 409);
  if (existing.rows[0]) await pool.query("DELETE FROM friend_requests WHERE id = $1", [existing.rows[0].id]);

  try {
    const result = await pool.query(
      `INSERT INTO friend_requests (requester_id, recipient_id)
       VALUES ($1, $2)
       RETURNING id, requester_id, recipient_id, status, created_at, updated_at`,
      [user.id, targetId]
    );
    return context.json({
      request: {
        ...result.rows[0],
        id: String(result.rows[0].id),
        requester_id: String(result.rows[0].requester_id),
        recipient_id: String(result.rows[0].recipient_id)
      }
    }, 201);
  } catch (error) {
    if (typeof error === "object" && error !== null && "code" in error && error.code === "23505") {
      return jsonError("A friend request already exists.", 409);
    }
    throw error;
  }
});

app.post("/api/friends/requests/:requestId/accept", requireAuth, async (context) => {
  await ensureSchema();
  const requestId = parseId(context.req.param("requestId"));
  if (requestId === null) return jsonError("Invalid friend request.", 400);
  const user = context.get("user");
  const result = await pool.query(
    `UPDATE friend_requests SET status = 'accepted', updated_at = now()
     WHERE id = $1 AND recipient_id = $2 AND status = 'pending'
     RETURNING id, status, requester_id, recipient_id, created_at, updated_at`,
    [requestId, user.id]
  );
  if (!result.rows[0]) return jsonError("Pending friend request not found.", 404);
  return context.json({ request: { ...result.rows[0], id: String(result.rows[0].id) } });
});

app.post("/api/friends/requests/:requestId/reject", requireAuth, async (context) => {
  await ensureSchema();
  const requestId = parseId(context.req.param("requestId"));
  if (requestId === null) return jsonError("Invalid friend request.", 400);
  const user = context.get("user");
  const result = await pool.query(
    `UPDATE friend_requests SET status = 'rejected', updated_at = now()
     WHERE id = $1 AND recipient_id = $2 AND status = 'pending'
     RETURNING id, status, requester_id, recipient_id, created_at, updated_at`,
    [requestId, user.id]
  );
  if (!result.rows[0]) return jsonError("Pending friend request not found.", 404);
  return context.json({ request: { ...result.rows[0], id: String(result.rows[0].id) } });
});

app.delete("/api/friends/:userId", requireAuth, async (context) => {
  await ensureSchema();
  const targetId = parseId(context.req.param("userId"));
  if (targetId === null) return jsonError("Invalid user.", 400);
  const user = context.get("user");
  const result = await pool.query(
    `DELETE FROM friend_requests
     WHERE status = 'accepted'
       AND ((requester_id = $1 AND recipient_id = $2) OR (requester_id = $2 AND recipient_id = $1))
     RETURNING id`,
    [user.id, targetId]
  );
  if (!result.rows[0]) return jsonError("Friend not found.", 404);
  return context.json({ removed: true });
});

app.get("/api/conversations", requireAuth, async (context) => {
  await ensureSchema();
  const user = context.get("user");
  const result = await pool.query(
    `SELECT dc.id, dc.created_at,
            u.id AS other_id, u.username AS other_username, u.avatar_data AS other_avatar,
            COALESCE(presence.is_online, FALSE) AS other_online,
            CASE
              WHEN presence.last_session_seen IS NULL AND u.last_seen_at IS NULL THEN NULL
              ELSE GREATEST(
                COALESCE(presence.last_session_seen, '-infinity'::timestamptz),
                COALESCE(u.last_seen_at, '-infinity'::timestamptz)
              )
            END AS other_last_seen_at,
            dm.id AS message_id, dm.content AS message_content, dm.user_id AS message_user_id,
            dm.created_at AS message_created_at,
            dm.image_available AS message_image_available,
            unread.unread_count
     FROM direct_conversations dc
     JOIN users u ON u.id = CASE WHEN dc.participant_low_id = $1 THEN dc.participant_high_id ELSE dc.participant_low_id END
     LEFT JOIN LATERAL (
       SELECT id, content, user_id, created_at, image_data IS NOT NULL AS image_available
       FROM direct_messages
       WHERE conversation_id = dc.id
       ORDER BY id DESC LIMIT 1
     ) dm ON true
     LEFT JOIN LATERAL (
       SELECT MAX(last_seen_at) AS last_session_seen,
              bool_or(last_seen_at > now() - interval '90 seconds') AS is_online
       FROM presence_sessions
       WHERE user_id = u.id
     ) presence ON true
     LEFT JOIN LATERAL (
       SELECT count(*)::integer AS unread_count
       FROM direct_messages unread_message
       LEFT JOIN read_state marker
         ON marker.user_id = $1 AND marker.scope = 'direct' AND marker.room_id = dc.id
       WHERE unread_message.conversation_id = dc.id
         AND unread_message.user_id <> $1
         AND unread_message.id > COALESCE(marker.last_read_message_id, 0)
     ) unread ON true
     WHERE dc.participant_low_id = $1 OR dc.participant_high_id = $1
     ORDER BY COALESCE(dm.id, 0) DESC, dc.id DESC`,
    [user.id]
  );
  return context.json({
    conversations: result.rows.map((row) => ({
      id: String(row.id),
      user: {
        id: String(row.other_id),
        username: row.other_username,
        avatar: row.other_avatar ?? null,
        online: row.other_online,
        last_seen_at: row.other_last_seen_at
      },
      created_at: row.created_at,
      unread_count: row.unread_count,
      last_message: row.message_id === null ? null : {
        id: String(row.message_id),
        user_id: String(row.message_user_id),
        content: row.message_content,
        created_at: row.message_created_at,
        image_available: row.message_image_available
      }
    }))
  });
});

app.post("/api/conversations", requireAuth, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with user_id.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const targetId = typeof source.user_id === "string" ? parseId(source.user_id) : null;
  const user = context.get("user");
  if (targetId === null || String(targetId) === user.id) return jsonError("Choose another valid user.", 400);
  const target = await pool.query("SELECT id FROM users WHERE id = $1", [targetId]);
  if (!target.rows[0]) return jsonError("User not found.", 404);
  const [lowId, highId] = BigInt(user.id) < BigInt(targetId) ? [user.id, targetId] : [targetId, user.id];
  const result = await pool.query(
    `INSERT INTO direct_conversations (participant_low_id, participant_high_id)
     VALUES ($1, $2)
     ON CONFLICT (participant_low_id, participant_high_id)
     DO UPDATE SET participant_low_id = EXCLUDED.participant_low_id
     RETURNING id, created_at`,
    [lowId, highId]
  );
  return context.json({ conversation: { id: String(result.rows[0].id), user_id: String(targetId), created_at: result.rows[0].created_at } }, 201);
});

app.get("/api/conversations/:conversationId/messages", requireAuth, async (context) => {
  await ensureSchema();
  const conversationId = parseId(context.req.param("conversationId"));
  if (conversationId === null) return jsonError("Invalid conversation.", 400);
  const user = context.get("user");
  const conversation = await pool.query(
    `SELECT dc.id FROM direct_conversations dc
     WHERE dc.id = $1 AND (dc.participant_low_id = $2 OR dc.participant_high_id = $2)`,
    [conversationId, user.id]
  );
  if (!conversation.rows[0]) return jsonError("Conversation not found.", 404);
  const rawLimit = context.req.query("limit") ?? "50";
  const limit = Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) return jsonError("Message limit must be between 1 and 100.", 400);
  const rawBefore = context.req.query("before");
  const before = rawBefore === undefined ? null : parseId(rawBefore);
  if (rawBefore !== undefined && before === null) return jsonError("Invalid message cursor.", 400);
  const result = await pool.query(
    `SELECT dm.id, dm.conversation_id, dm.user_id, u.username, u.avatar_data AS avatar,
            dm.content, dm.image_data, dm.created_at
     FROM direct_messages dm JOIN users u ON u.id = dm.user_id
     WHERE dm.conversation_id = $1 AND ($2::bigint IS NULL OR dm.id < $2)
     ORDER BY dm.id DESC LIMIT $3`,
    [conversationId, before, limit]
  );
  return context.json({ messages: result.rows.reverse().map((row) => ({ ...row, id: String(row.id), conversation_id: String(row.conversation_id), user_id: String(row.user_id) })) });
});

app.post("/api/conversations/:conversationId/messages", requireAuth, async (context) => {
  await ensureSchema();
  const conversationId = parseId(context.req.param("conversationId"));
  if (conversationId === null) return jsonError("Invalid conversation.", 400);
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with a message.", 400);
  }
  const message = validatedMessage(body);
  if (!message) return jsonError("Message must contain 1–2000 characters.", 400);
  const user = context.get("user");
  const conversation = await pool.query(
    `SELECT id FROM direct_conversations
     WHERE id = $1 AND (participant_low_id = $2 OR participant_high_id = $2)`,
    [conversationId, user.id]
  );
  if (!conversation.rows[0]) return jsonError("Conversation not found.", 404);
  if (!(await allowRate("message_rate_limits", user.id, 30))) {
    return jsonError("You're sending messages too quickly. Try again in a minute.", 429);
  }
  const result = await pool.query(
    `INSERT INTO direct_messages (conversation_id, user_id, content, image_data)
     VALUES ($1, $2, $3, $4)
     RETURNING id, conversation_id, user_id, content, image_data, created_at`,
    [conversationId, user.id, message.content, message.image_data ?? null]
  );
  return context.json({ message: { ...result.rows[0], id: String(result.rows[0].id), conversation_id: String(result.rows[0].conversation_id), user_id: user.id, username: user.username } }, 201);
});

app.post("/api/read-state", requireAuth, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with a read scope, room, and message.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const scope = source.scope;
  const roomId = typeof source.room_id === "string" ? parseId(source.room_id) : null;
  const messageId = typeof source.last_read_message_id === "string"
    ? parseId(source.last_read_message_id)
    : null;
  if ((scope !== "channel" && scope !== "direct") || roomId === null || messageId === null) {
    return jsonError("Read state requires a valid scope, room_id, and last_read_message_id.", 400);
  }

  const user = context.get("user");
  if (scope === "channel") {
    const channel = await pool.query("SELECT id, server_id FROM channels WHERE id = $1", [roomId]);
    if (!channel.rows[0]) return jsonError("Channel not found.", 404);
    if (channel.rows[0].server_id !== null) {
      const membership = await pool.query(
        "SELECT 1 FROM server_memberships WHERE server_id = $1 AND user_id = $2",
        [channel.rows[0].server_id, user.id]
      );
      if (!membership.rows[0]) return jsonError("Join this server to update its read state.", 403);
    }
    const markerMessage = await pool.query(
      "SELECT 1 FROM messages WHERE id = $1 AND channel_id = $2",
      [messageId, roomId]
    );
    if (!markerMessage.rows[0]) return jsonError("Message not found in this channel.", 404);
  } else {
    const conversation = await pool.query(
      `SELECT id FROM direct_conversations
       WHERE id = $1 AND (participant_low_id = $2 OR participant_high_id = $2)`,
      [roomId, user.id]
    );
    if (!conversation.rows[0]) return jsonError("Conversation not found.", 404);
    const markerMessage = await pool.query(
      "SELECT 1 FROM direct_messages WHERE id = $1 AND conversation_id = $2",
      [messageId, roomId]
    );
    if (!markerMessage.rows[0]) return jsonError("Message not found in this conversation.", 404);
  }

  await pool.query(
    `INSERT INTO read_state (user_id, scope, room_id, last_read_message_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (user_id, scope, room_id) DO UPDATE SET
       last_read_message_id = GREATEST(read_state.last_read_message_id, EXCLUDED.last_read_message_id)`,
    [user.id, scope, roomId, messageId]
  );
  return context.json({ ok: true });
});

app.post("/api/presence/heartbeat", requireAuth, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with a session_id UUID.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const sessionId = parseSessionId(source.session_id);
  if (!sessionId) return jsonError("Send a valid session_id UUID.", 400);
  const user = context.get("user");
  const result = await pool.query(
    `INSERT INTO presence_sessions (session_id, user_id, last_seen_at)
     VALUES ($1, $2, clock_timestamp())
     ON CONFLICT (session_id) DO UPDATE SET last_seen_at = clock_timestamp()
       WHERE presence_sessions.user_id = EXCLUDED.user_id
     RETURNING session_id`,
    [sessionId, user.id]
  );
  if (!result.rows[0]) return jsonError("That presence session belongs to another account.", 409);
  return context.json({ ok: true });
});

app.delete("/api/presence", requireAuth, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with a session_id UUID.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const sessionId = parseSessionId(source.session_id);
  if (!sessionId) return jsonError("Send a valid session_id UUID.", 400);
  const user = context.get("user");
  const removed = await pool.query(
    "DELETE FROM presence_sessions WHERE session_id = $1 AND user_id = $2 RETURNING user_id",
    [sessionId, user.id]
  );
  if (removed.rows[0]) {
    await pool.query(
      `UPDATE users SET last_seen_at = clock_timestamp()
       WHERE id = $1 AND NOT EXISTS (
         SELECT 1 FROM presence_sessions
         WHERE user_id = $1 AND last_seen_at > clock_timestamp() - interval '90 seconds'
       )`,
      [user.id]
    );
  }
  return context.json({ ok: true });
});

app.get("/api/search", requireAuth, async (context) => {
  await ensureSchema();
  const query = (context.req.query("query") ?? "").trim();
  if ([...query].length < 2 || [...query].length > 80) {
    return jsonError("Search query must contain 2–80 characters.", 400);
  }
  const user = context.get("user");
  const escapedQuery = query.replace(/[\\%_]/g, "\\$&");
  const result = await pool.query(
    `SELECT scope, room_id::text AS room_id, message_id::text AS message_id,
            title, username, content, image_available, created_at, server_id, channel_name
     FROM (
       SELECT 'channel'::text AS scope, c.id AS room_id, m.id AS message_id,
              c.name::text AS title, u.username, m.content,
              (m.image_data IS NOT NULL) AS image_available, m.created_at,
              c.server_id::text AS server_id,
              CASE WHEN c.server_id IS NULL THEN NULL ELSE c.name END AS channel_name
       FROM messages m
       JOIN channels c ON c.id = m.channel_id
       JOIN users u ON u.id = m.user_id
       WHERE m.content ILIKE $2 ESCAPE E'\\\\'
         AND (c.server_id IS NULL OR EXISTS (
           SELECT 1 FROM server_memberships sm
           WHERE sm.server_id = c.server_id AND sm.user_id = $1
         ))
       UNION ALL
       SELECT 'direct'::text AS scope, dc.id AS room_id, dm.id AS message_id,
              other_user.username::text AS title, sender.username, dm.content,
              (dm.image_data IS NOT NULL) AS image_available, dm.created_at,
              NULL::text AS server_id, NULL::text AS channel_name
       FROM direct_messages dm
       JOIN direct_conversations dc ON dc.id = dm.conversation_id
       JOIN users sender ON sender.id = dm.user_id
       JOIN users other_user ON other_user.id = CASE
         WHEN dc.participant_low_id = $1 THEN dc.participant_high_id
         ELSE dc.participant_low_id
       END
       WHERE dm.content ILIKE $2 ESCAPE E'\\\\'
         AND (dc.participant_low_id = $1 OR dc.participant_high_id = $1)
     ) matches
     ORDER BY matches.created_at DESC, matches.message_id DESC
     LIMIT 50`,
    [user.id, `%${escapedQuery}%`]
  );
  return context.json({ results: result.rows });
});

app.get("/api/servers", requireAuth, async (context) => {
  await ensureSchema();
  const user = context.get("user");
  const result = await pool.query(
    `SELECT s.id, s.name, s.description, s.owner_id, s.created_at,
            (SELECT count(*)::integer FROM server_memberships sm WHERE sm.server_id = s.id) AS member_count,
            EXISTS (SELECT 1 FROM server_memberships sm WHERE sm.server_id = s.id AND sm.user_id = $1) AS is_member
     FROM servers s ORDER BY lower(s.name), s.id`,
    [user.id]
  );
  return context.json({ servers: result.rows.map((row) => ({ ...row, id: String(row.id), owner_id: String(row.owner_id) })) });
});

app.post("/api/servers", requireAuth, async (context) => {
  await ensureSchema();
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with a server name.", 400);
  }
  const source = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const name = typeof source.name === "string" ? source.name.trim() : "";
  const description = typeof source.description === "string" ? source.description.trim() : "";
  if (name.length < 1 || [...name].length > 64 || [...description].length > 240) {
    return jsonError("Server names must be 1–64 characters and descriptions at most 240 characters.", 400);
  }
  const user = context.get("user");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const serverResult = await client.query(
      "INSERT INTO servers (name, description, owner_id) VALUES ($1, $2, $3) RETURNING id, name, description, owner_id, created_at",
      [name, description, user.id]
    );
    const server = serverResult.rows[0];
    await client.query("INSERT INTO server_memberships (server_id, user_id, role) VALUES ($1, $2, 'owner')", [server.id, user.id]);
    const channelResult = await client.query(
      "INSERT INTO channels (name, description, position, server_id) VALUES ('general', 'Chat with server members.', 1, $1) RETURNING id, name, description, position, server_id",
      [server.id]
    );
    await client.query("COMMIT");
    return context.json({
      server: { ...server, id: String(server.id), owner_id: String(server.owner_id), member_count: 1, is_member: true },
      channels: channelResult.rows.map((row) => ({ ...row, id: String(row.id), server_id: String(row.server_id) }))
    }, 201);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
});

app.get("/api/servers/:serverId", requireAuth, async (context) => {
  await ensureSchema();
  const serverId = parseId(context.req.param("serverId"));
  if (serverId === null) return jsonError("Invalid server.", 400);
  const user = context.get("user");
  const result = await pool.query(
    `SELECT s.id, s.name, s.description, s.owner_id, s.created_at,
            (SELECT count(*)::integer FROM server_memberships sm WHERE sm.server_id = s.id) AS member_count,
            EXISTS (SELECT 1 FROM server_memberships sm WHERE sm.server_id = s.id AND sm.user_id = $2) AS is_member
     FROM servers s WHERE s.id = $1`,
    [serverId, user.id]
  );
  if (!result.rows[0]) return jsonError("Server not found.", 404);
  const row = result.rows[0];
  return context.json({ server: { ...row, id: String(row.id), owner_id: String(row.owner_id) } });
});

app.post("/api/servers/:serverId/join", requireAuth, async (context) => {
  await ensureSchema();
  const serverId = parseId(context.req.param("serverId"));
  if (serverId === null) return jsonError("Invalid server.", 400);
  const user = context.get("user");
  const result = await pool.query(
    `INSERT INTO server_memberships (server_id, user_id)
     SELECT id, $2 FROM servers WHERE id = $1
     ON CONFLICT (server_id, user_id) DO NOTHING
     RETURNING server_id`,
    [serverId, user.id]
  );
  if (!result.rows[0]) {
    const exists = await pool.query("SELECT id FROM servers WHERE id = $1", [serverId]);
    if (!exists.rows[0]) return jsonError("Server not found.", 404);
  }
  return context.json({ server_id: String(serverId), joined: true });
});

app.delete("/api/servers/:serverId/membership", requireAuth, async (context) => {
  await ensureSchema();
  const serverId = parseId(context.req.param("serverId"));
  if (serverId === null) return jsonError("Invalid server.", 400);
  const user = context.get("user");
  const result = await pool.query(
    "DELETE FROM server_memberships WHERE server_id = $1 AND user_id = $2 AND role <> 'owner' RETURNING server_id",
    [serverId, user.id]
  );
  if (!result.rows[0]) return jsonError("Membership not found or owner cannot leave the server.", 404);
  return context.json({ server_id: String(serverId), left: true });
});

app.delete("/api/servers/:serverId", requireAuth, async (context) => {
  await ensureSchema();
  const serverId = parseId(context.req.param("serverId"));
  if (serverId === null) return jsonError("Invalid server.", 400);
  const user = context.get("user");
  const result = await pool.query(
    "DELETE FROM servers WHERE id = $1 AND owner_id = $2 RETURNING id",
    [serverId, user.id]
  );
  if (!result.rows[0]) return jsonError("Server not found or only its owner can delete it.", 404);
  return context.json({ deleted: true, server_id: String(result.rows[0].id) });
});

app.get("/api/servers/:serverId/channels", requireAuth, async (context) => {
  await ensureSchema();
  const serverId = parseId(context.req.param("serverId"));
  if (serverId === null) return jsonError("Invalid server.", 400);
  const user = context.get("user");
  const membership = await pool.query("SELECT 1 FROM server_memberships WHERE server_id = $1 AND user_id = $2", [serverId, user.id]);
  if (!membership.rows[0]) return jsonError("Join this server to view its channels.", 403);
  const result = await pool.query(
    `SELECT c.id, c.server_id, c.name, c.description, c.position,
            (SELECT count(*)::integer
             FROM messages m
             LEFT JOIN read_state marker
               ON marker.user_id = $2 AND marker.scope = 'channel' AND marker.room_id = c.id
             WHERE m.channel_id = c.id AND m.user_id <> $2
               AND m.id > COALESCE(marker.last_read_message_id, 0)) AS unread_count
     FROM channels c
     WHERE c.server_id = $1
     ORDER BY c.position, c.id`,
    [serverId, user.id]
  );
  return context.json({ channels: result.rows.map((row) => ({ ...row, id: String(row.id), server_id: String(row.server_id) })) });
});

app.get("/api/channels", requireAuth, async (context) => {
  await ensureSchema();
  const user = context.get("user");
  const result = await pool.query(
    `SELECT c.id, c.name, c.description,
            (SELECT count(*)::integer FROM users) AS member_count,
            (SELECT count(*)::integer
             FROM messages m
             LEFT JOIN read_state marker
               ON marker.user_id = $1 AND marker.scope = 'channel' AND marker.room_id = c.id
             WHERE m.channel_id = c.id AND m.user_id <> $1
               AND m.id > COALESCE(marker.last_read_message_id, 0)) AS unread_count
     FROM channels c WHERE c.server_id IS NULL
     ORDER BY c.position, c.id`,
    [user.id]
  );
  return context.json({ channels: result.rows });
});

app.get("/api/channels/:channelId/messages", requireAuth, async (context) => {
  await ensureSchema();
  const channelId = parseId(context.req.param("channelId"));
  if (channelId === null) return jsonError("Invalid channel.", 400);
  const rawLimit = context.req.query("limit") ?? "50";
  const limit = Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    return jsonError("Message limit must be between 1 and 100.", 400);
  }
  const rawBefore = context.req.query("before");
  const before = rawBefore === undefined ? null : parseId(rawBefore);
  if (rawBefore !== undefined && before === null) return jsonError("Invalid message cursor.", 400);
  const channel = await pool.query("SELECT id, server_id FROM channels WHERE id = $1", [channelId]);
  if (!channel.rows[0]) return jsonError("Channel not found.", 404);
  if (channel.rows[0].server_id !== null) {
    const membership = await pool.query(
      "SELECT 1 FROM server_memberships WHERE server_id = $1 AND user_id = $2",
      [channel.rows[0].server_id, context.get("user").id]
    );
    if (!membership.rows[0]) return jsonError("Join this server to view its messages.", 403);
  }
  const result = await pool.query(
    `SELECT m.id, m.channel_id, m.user_id, u.username, u.avatar_data AS avatar,
            m.content, m.image_data, m.created_at
     FROM messages m
     JOIN users u ON u.id = m.user_id
     WHERE m.channel_id = $1 AND ($2::bigint IS NULL OR m.id < $2)
     ORDER BY m.id DESC
     LIMIT $3`,
    [channelId, before, limit]
  );
  return context.json({ messages: result.rows.reverse() });
});

app.post("/api/channels/:channelId/messages", requireAuth, async (context) => {
  await ensureSchema();
  const channelId = parseId(context.req.param("channelId"));
  if (channelId === null) return jsonError("Invalid channel.", 400);
  let body: unknown;
  try {
    body = await context.req.json();
  } catch {
    return jsonError("Send valid JSON with a message.", 400);
  }
  const message = validatedMessage(body);
  if (!message) return jsonError("Message must contain 1–2000 characters.", 400);
  const user = context.get("user");
  if (!(await allowRate("message_rate_limits", user.id, 30))) {
    return jsonError("You're sending messages too quickly. Try again in a minute.", 429);
  }
  const channel = await pool.query(
    "SELECT id, server_id FROM channels WHERE id = $1",
    [channelId]
  );
  if (!channel.rows[0]) return jsonError("Channel not found.", 404);
  if (channel.rows[0].server_id !== null) {
    const membership = await pool.query(
      "SELECT 1 FROM server_memberships WHERE server_id = $1 AND user_id = $2",
      [channel.rows[0].server_id, user.id]
    );
    if (!membership.rows[0]) return jsonError("Join this server to send messages.", 403);
  }
  const result = await pool.query(
    `WITH inserted AS (
       INSERT INTO messages (channel_id, user_id, content, image_data)
       VALUES ($1, $2, $3, $4)
       RETURNING id, channel_id, user_id, content, image_data, created_at
     )
     SELECT inserted.*, u.username, u.avatar_data AS avatar
     FROM inserted JOIN users u ON u.id = inserted.user_id`,
    [channelId, user.id, message.content, message.image_data ?? null]
  );
  const savedMessage = result.rows[0];
  return context.json({ message: savedMessage }, 201);
});

app.get("/ws", requireAuth, upgradeWebSocket((context) => ({
  onOpen: async (_event, socketContext) => {
    const socket = socketContext.raw;
    sockets.set(socket, context.get("user").id);
    try {
      await ensureSchema();
      await startMessageFeed();
      socketContext.send(JSON.stringify({ type: "ready" }));
    } catch (error) {
      console.error("Could not start Aether realtime feed:", error);
      socketContext.close(1011, "Realtime service unavailable");
      releaseMessageFeed(socket);
    }
  },
  onClose: (_event, socketContext) => {
    releaseMessageFeed(socketContext.raw);
  },
  onError: (_event, socketContext) => {
    releaseMessageFeed(socketContext.raw);
  }
})));

app.notFound((context) => context.json({ error: "Not found." }, 404));
app.onError((error, context) => {
  console.error("Aether request failed:", error);
  return context.json({ error: "The server could not complete that request." }, 500);
});

export default {
  fetch: (request: Request) => app.fetch(request)
};
