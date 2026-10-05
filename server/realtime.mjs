export function canReceiveRealtimeEvent(audience, userId) {
  if (audience?.scope === "public-channel") return true;
  if (audience?.scope === "server-channel") {
    return Array.isArray(audience.memberIds) && audience.memberIds.includes(userId);
  }
  if (audience?.scope === "direct-message") {
    return Array.isArray(audience.recipientIds) && audience.recipientIds.includes(userId);
  }
  return false;
}
