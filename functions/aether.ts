import { attachDatabasePool } from "@neon/functions";
import { upgradeWebSocket } from "@neon/functions/hono";
import { Hono, type MiddlewareHandler } from "hono";
import bcrypt from "bcryptjs";
import jwt, { type JwtPayload } from "jsonwebtoken";
import { Client, Pool, type PoolClient } from "pg";
import {
  parseId,
  validateCredentials,
  validateMessage,
  type ValidCredentials,
  type ValidMessage
} from "../server/validation.mjs";

type PublicUser = { id: string; username: string };
type AuthUser = PublicUser;
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

const sockets = new Set<WebSocket>();
let schemaPromise: Promise<void> | null = null;
let feedPromise: Promise<void> | null = null;
let feedTimer: ReturnType<typeof setInterval> | null = null;
let feedCursor = "0";
let feedPolling = false;

const app = new Hono<AppEnvironment>();

function jsonError(message: string, status: 400 | 401 | 404 | 429 | 500 | 503) {
  return Response.json({ error: message }, { status });
}

function credentials(value: unknown): ValidCredentials | null {
  const source = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const result = validateCredentials(source.username, source.password);
  return "error" in result ? null : result;
}

function validatedMessage(value: unknown): ValidMessage | null {
  const source = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const result = validateMessage(source.content);
  return "error" in result ? null : result;
}

function publicUser(row: { id: string | number; username: string }): PublicUser {
  return { id: String(row.id), username: row.username };
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
      CREATE TABLE IF NOT EXISTS channels (
        id BIGSERIAL PRIMARY KEY,
        name VARCHAR(32) NOT NULL UNIQUE,
        description VARCHAR(160) NOT NULL,
        position INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS messages (
        id BIGSERIAL PRIMARY KEY,
        channel_id BIGINT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        content VARCHAR(2000) NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
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
      INSERT INTO channels (name, description, position) VALUES
        ('general', 'Chat with everyone in the community.', 1),
        ('gaming', 'Talk games, teams, and what you are playing.', 2),
        ('introductions', 'Say hello and meet the community.', 3)
      ON CONFLICT (name) DO NOTHING;
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
    context.set("user", { id: payload.sub, username: payload.username });
    await next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError || error instanceof jwt.JsonWebTokenError) {
      return context.json({ error: "Your session expired. Sign in again." }, 401);
    }
    throw error;
  }
};

function broadcast(event: SocketEvent): void {
  const payload = JSON.stringify(event);
  for (const socket of sockets) {
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
    const result = await pool.query(
      `SELECT m.id, m.channel_id, m.user_id, u.username, m.content, m.created_at
       FROM messages m
       JOIN users u ON u.id = m.user_id
       WHERE m.id > $1::bigint
       ORDER BY m.id ASC
       LIMIT 100`,
      [feedCursor]
    );
    for (const row of result.rows) {
      feedCursor = String(row.id);
      broadcast({ type: "message", message: row });
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
    "SELECT id, username, password_hash FROM users WHERE username_key = $1",
    [details.username.toLowerCase()]
  );
  const row = result.rows[0];
  const matches = row ? await bcrypt.compare(details.password, row.password_hash) : false;
  if (!matches) return jsonError("Username or password is incorrect.", 401);
  const user = publicUser(row);
  return context.json({ token: signToken(user), user });
});

app.get("/api/me", requireAuth, async (context) => {
  await ensureSchema();
  const currentUser = context.get("user");
  const result = await pool.query("SELECT id, username FROM users WHERE id = $1", [currentUser.id]);
  if (!result.rows[0]) return jsonError("Account no longer exists.", 401);
  return context.json({ user: publicUser(result.rows[0]) });
});

app.get("/api/channels", requireAuth, async (context) => {
  await ensureSchema();
  const result = await pool.query(
    `SELECT c.id, c.name, c.description,
            (SELECT count(*)::integer FROM users) AS member_count
     FROM channels c
     ORDER BY c.position, c.id`
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
  const channel = await pool.query("SELECT id FROM channels WHERE id = $1", [channelId]);
  if (!channel.rows[0]) return jsonError("Channel not found.", 404);
  const result = await pool.query(
    `SELECT m.id, m.channel_id, m.user_id, u.username, m.content, m.created_at
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
    "SELECT id FROM channels WHERE id = $1",
    [channelId]
  );
  if (!channel.rows[0]) return jsonError("Channel not found.", 404);
  const result = await pool.query(
    `INSERT INTO messages (channel_id, user_id, content)
     VALUES ($1, $2, $3)
     RETURNING id, channel_id, user_id, content, created_at`,
    [channelId, user.id, message.content]
  );
  const savedMessage = { ...result.rows[0], username: user.username };
  return context.json({ message: savedMessage }, 201);
});

app.get("/ws", requireAuth, upgradeWebSocket((context) => ({
  onOpen: async (_event, socketContext) => {
    const socket = socketContext.raw;
    sockets.add(socket);
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
