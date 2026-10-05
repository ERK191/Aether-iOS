export function validateCredentials(usernameValue, passwordValue) {
  const username = typeof usernameValue === "string" ? usernameValue.trim() : "";
  const password = typeof passwordValue === "string" ? passwordValue : "";
  if (!/^[A-Za-z0-9_]{3,24}$/.test(username)) {
    return { error: "Username must be 3–24 letters, numbers, or underscores." };
  }
  if (password.length < 8 || Buffer.byteLength(password, "utf8") > 72) {
    return { error: "Password must be at least 8 characters and at most 72 bytes." };
  }
  return { username, password };
}

export function validateMessage(value) {
  if (typeof value !== "string") return { error: "Message must contain 1–2000 characters." };
  const content = value.trim();
  if (content.length === 0 || [...content].length > 2000) {
    return { error: "Message must contain 1–2000 characters." };
  }
  return { content };
}

export function parseId(value) {
  if (typeof value !== "string" || !/^[1-9][0-9]{0,14}$/.test(value)) return null;
  const id = Number(value);
  return Number.isSafeInteger(id) ? id : null;
}
