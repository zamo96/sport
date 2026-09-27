import { prisma } from "@/lib/prisma";
import { listStoredChatImages, removeStoredChatImage } from "@/server/chat-media";

/** A photo picked for a message but never sent is kept this long in case the message is still being written. */
const UNCLAIMED_CHAT_MEDIA_TTL_MS = 24 * 60 * 60 * 1000;
/** A file younger than this may belong to an upload whose database row is not written yet. */
const UNTRACKED_FILE_GRACE_MS = 60 * 60 * 1000;
const KEY_LOOKUP_CHUNK = 1000;

/**
 * Chat photos live in object storage, so the database cascade that removes a
 * deleted account's chats, lobbies and messages leaves the files behind. This
 * removes photos no message uses any more, uploads that were never sent, and
 * files the database no longer knows about (their rows went with an account).
 */
export async function removeUnusedChatMedia(now = new Date()) {
  const unused = await prisma.chatMediaAsset.findMany({
    where: {
      OR: [
        { claimedAt: null, createdAt: { lt: new Date(now.getTime() - UNCLAIMED_CHAT_MEDIA_TTL_MS) } },
        { claimedAt: { not: null }, chatMessageMedia: null, searchMessageMedia: null }
      ]
    },
    select: { id: true, storageKey: true }
  });
  if (unused.length) {
    await Promise.all(unused.map((asset) => removeStoredChatImage(asset.storageKey)));
    await prisma.chatMediaAsset.deleteMany({ where: { id: { in: unused.map((asset) => asset.id) } } });
  }

  const settled = (await listStoredChatImages()).filter(
    (file) => now.getTime() - file.storedAt.getTime() > UNTRACKED_FILE_GRACE_MS
  );
  const known = new Set<string>();
  for (let start = 0; start < settled.length; start += KEY_LOOKUP_CHUNK) {
    const keys = settled.slice(start, start + KEY_LOOKUP_CHUNK).map((file) => file.storageKey);
    const rows = await prisma.chatMediaAsset.findMany({ where: { storageKey: { in: keys } }, select: { storageKey: true } });
    rows.forEach((row) => known.add(row.storageKey));
  }
  const untracked = settled.filter((file) => !known.has(file.storageKey));
  await Promise.all(untracked.map((file) => removeStoredChatImage(file.storageKey)));

  return { unusedAssets: unused.length, untrackedFiles: untracked.length };
}

/** Files of photos a person uploaded; read before their account is deleted, removed right after. */
export async function listUploadedChatMedia(userId: string) {
  const assets = await prisma.chatMediaAsset.findMany({ where: { uploaderUserId: userId }, select: { storageKey: true } });
  return assets.map((asset) => asset.storageKey);
}

export async function removeChatMediaFiles(storageKeys: string[]) {
  await Promise.all(storageKeys.map((storageKey) => removeStoredChatImage(storageKey)));
}
