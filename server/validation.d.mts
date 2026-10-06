export interface ValidationError {
  error: string;
}

export interface ValidCredentials {
  username: string;
  password: string;
}

export type ValidMessage =
  | { content: string; image_data?: string }
  | ValidationError;

export interface ValidAvatar {
  avatar: string | null;
}

export function validateCredentials(
  usernameValue: unknown,
  passwordValue: unknown
): ValidCredentials | ValidationError;

export function validateMessage(
  value: unknown,
  imageDataValue?: unknown
): ValidMessage;
export function validateAvatar(value: unknown): ValidAvatar | ValidationError;
export function parseId(value: string): number | null;
