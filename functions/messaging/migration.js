"use strict";

// Pure migration planner: no guessed membership and no dropped records.
function planConversation(id, data, messages, createdAt) {
  const legacy = [data.participant1Id, data.participant2Id].filter((id) => typeof id === "string" && id);
  const ids = data.participantIds || legacy;
  if (!Array.isArray(ids) || ids.length < 2 || ids.length > 100 || new Set(ids).size !== ids.length ||
      ids.some((id) => typeof id !== "string" || !id || id.includes("/")) ||
      legacy.some((id) => !ids.includes(id)) || (!data.isGroup && ids.length !== 2)) {
    throw new Error("ambiguous-membership");
  }
  if (data.messagingVersion === 2) return null;
  const sorted = messages.map((message) => {
    if (!ids.includes(message.data.senderId) ||
        (message.data.receiverId && !ids.includes(message.data.receiverId)) ||
        typeof message.data.content !== "string") throw new Error("invalid-message");
    const timestamp = message.data.timestamp || message.createdAt;
    if (typeof timestamp?.toMillis !== "function") throw new Error("invalid-timestamp");
    return {...message, timestamp};
  }).sort((a, b) => a.timestamp.toMillis() - b.timestamp.toMillis() || a.id.localeCompare(b.id));
  const totals = Object.fromEntries(ids.map((id) => [id, 0]));
  const readTotals = {...totals};
  const readSequences = {...totals};
  const seenUnread = new Set();
  const updates = sorted.map((message, index) => {
    for (const uid of ids) {
      if (uid !== message.data.senderId) {
        totals[uid]++;
        const read = data.isGroup ? message.data.readByUserIds?.includes(uid) : message.data.isRead === true;
        if (!read) seenUnread.add(uid);
      }
      if (!seenUnread.has(uid)) {
        readTotals[uid] = totals[uid];
        readSequences[uid] = index + 1;
      }
    }
    return {id: message.id, patch: {conversationId: id, timestamp: message.timestamp,
      sequence: index + 1, recipientTotals: {...totals}}};
  });
  const last = sorted.at(-1);
  const time = last?.timestamp || data.lastMessageTime || createdAt;
  if (typeof time?.toMillis !== "function") throw new Error("invalid-conversation-timestamp");
  return {messages: updates, conversation: {participantIds: ids, messagingVersion: 2,
    sequence: sorted.length, receivedTotals: totals, readTotals, readSequences,
    unreadCounts: Object.fromEntries(ids.map((uid) => [uid, totals[uid] - readTotals[uid]])),
    lastMessage: last?.data.content || data.lastMessage || "", lastMessageTime: time,
    ...(last ? {lastMessageSenderId: last.data.senderId} : {})}};
}

module.exports = {planConversation};
