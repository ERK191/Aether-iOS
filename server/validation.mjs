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

const MAX_MESSAGE_IMAGE_BYTES = 512 * 1024;

export function validateMessage(value, imageDataValue) {
  if (typeof value !== "string") return { error: "Message must contain 1–2000 characters." };
  const content = value.trim();
  if ([...content].length > 2000) {
    return { error: "Message must contain 1–2000 characters." };
  }
  if (imageDataValue !== undefined) {
    const image = validateMessageImage(imageDataValue);
    if ("error" in image) return image;
    return { content, image_data: image.image_data };
  }
  if (content.length === 0) return { error: "Message must contain 1–2000 characters." };
  return { content };
}

function validateMessageImage(value) {
  if (typeof value !== "string") return { error: "Message image must be a PNG, JPEG, or WebP data URL." };
  const match = /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/]+={0,2})$/.exec(value);
  if (!match || match[2].length % 4 !== 0 ||
      match[2].length > Math.ceil(MAX_MESSAGE_IMAGE_BYTES / 3) * 4) {
    return { error: "Message image must be a PNG, JPEG, or WebP data URL no larger than 512 KiB." };
  }

  const bytes = Buffer.from(match[2], "base64");
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_MESSAGE_IMAGE_BYTES ||
      bytes.toString("base64") !== match[2]) {
    return { error: "Message image must be a PNG, JPEG, or WebP data URL no larger than 512 KiB." };
  }

  const mime = match[1];
  const validSignature =
    (mime === "image/png" && bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) ||
    (mime === "image/jpeg" && bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) ||
    (mime === "image/webp" && bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP");
  if (!validSignature) return { error: "Message image data does not match its image type." };

  return { image_data: value };
}

const MAX_AVATAR_BYTES = 1024 * 1024;

export function validateAvatar(value) {
  if (value === null) return { avatar: null };
  if (typeof value !== "string") return { error: "Avatar must be a PNG, JPEG, GIF, or WebP data URL." };

  const match = /^data:(image\/(?:png|jpeg|gif|webp));base64,([A-Za-z0-9+/]+={0,2})$/.exec(value);
  if (!match || match[2].length % 4 !== 0) {
    return { error: "Avatar must be a PNG, JPEG, GIF, or WebP data URL." };
  }
  if (match[2].length > Math.ceil(MAX_AVATAR_BYTES / 3) * 4) {
    return { error: "Avatar image must be between 1 byte and 1 MiB." };
  }

  const bytes = Buffer.from(match[2], "base64");
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_AVATAR_BYTES ||
      bytes.toString("base64") !== match[2]) {
    return { error: "Avatar image must be between 1 byte and 1 MiB." };
  }

  const mime = match[1];
  const validSignature =
    (mime === "image/png" && bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) ||
    (mime === "image/jpeg" && bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) ||
    (mime === "image/gif" && bytes.length >= 6 && ["GIF87a", "GIF89a"].includes(bytes.toString("ascii", 0, 6))) ||
    (mime === "image/webp" && bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP");
  if (!validSignature) return { error: "Avatar data does not match its image type." };

  return { avatar: value };
}

export function parseId(value) {
  if (typeof value !== "string" || !/^[1-9][0-9]{0,14}$/.test(value)) return null;
  const id = Number(value);
  return Number.isSafeInteger(id) ? id : null;
}
