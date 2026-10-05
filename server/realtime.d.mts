export type RealtimeAudience =
  | { scope: "public-channel" }
  | { scope: "server-channel"; memberIds: string[] }
  | { scope: "direct-message"; recipientIds: string[] };

export function canReceiveRealtimeEvent(audience: RealtimeAudience, userId: string): boolean;
