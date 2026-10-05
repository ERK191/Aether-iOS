export interface ValidationError {
  error: string;
}

export interface ValidCredentials {
  username: string;
  password: string;
}

export interface ValidMessage {
  content: string;
}

export interface ValidAvatar {
  avatar: string | null;
}

export function validateCredentials(
  usernameValue: unknown,
  passwordValue: unknown
): ValidCredentials | ValidationError;

export function validateMessage(value: unknown): ValidMessage | ValidationError;
export function validateAvatar(value: unknown): ValidAvatar | ValidationError;
export function parseId(value: string): number | null;
