import { RegularPairOccurrenceStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/push";
import { prisma } from "@/lib/prisma";
import { formatLocalDateTime } from "@/lib/timezone";
import { publishRealtimeEventToUsers } from "@/server/realtime";

/**
 * Что именно сделал игрок со слотом. Текст пуша отличается, а адресат — нет:
 * это всегда второй игрок пары, потому что подтверждения ждут от него.
 */
export type RegularOccurrenceChange = "proposal" | "confirmed" | "declined";

/**
 * Экран подтверждения слота живёт внутри поиска пары: и в iOS, и в Android
 * `/play/searches/<id>` открывает карточку пары с кнопками «Смогу / Не смогу»,
 * а на вебе — лобби этого поиска. Как только слот подтверждён обоими, у него
 * появляется игра, и вести нужно уже в неё.
 */
function resolveHref(occurrence: { gameRequest: { id: string } | null; regularPair: { gameSearchId: string } }) {
  return occurrence.gameRequest
    ? `/play/games/${occurrence.gameRequest.id}`
    : `/play/searches/${occurrence.regularPair.gameSearchId}`;
}

function playerName(name: string | null | undefined) {
  return name?.trim() || "Игрок";
}

/**
 * Пуш второму игроку пары о том, что со слотом что-то произошло и теперь ход
 * за ним. Вызывается после транзакции: до коммита ни адресата, ни итогового
 * статуса слота знать нельзя — подтверждение второго игрока могло сразу
 * закрыть слот и создать игру.
 */
export async function notifyRegularOccurrencePartner({
  occurrenceId,
  actorUserId,
  change
}: {
  occurrenceId: string;
  actorUserId: string;
  change: RegularOccurrenceChange;
}) {
  const occurrence = await prisma.regularPairOccurrence.findUnique({
    where: { id: occurrenceId },
    select: {
      id: true,
      scheduledAt: true,
      durationMinutes: true,
      status: true,
      proposedCourt: { select: { name: true } },
      gameRequest: { select: { id: true } },
      regularPair: {
        select: {
          id: true,
          matchId: true,
          gameSearchId: true,
          preferredCourt: { select: { name: true } },
          createdByUser: { select: { id: true, name: true, timezone: true, notificationGames: true, notificationSound: true } },
          partnerUser: { select: { id: true, name: true, timezone: true, notificationGames: true, notificationSound: true } }
        }
      }
    }
  });

  if (!occurrence) {
    return;
  }

  const { createdByUser, partnerUser } = occurrence.regularPair;
  const actor = createdByUser.id === actorUserId ? createdByUser : partnerUser.id === actorUserId ? partnerUser : null;

  if (!actor) {
    return;
  }

  const recipient = actor.id === createdByUser.id ? partnerUser : createdByUser;
  const href = resolveHref(occurrence);

  // Открытый экран пары обновляется у обоих: у автора действия — по ответу
  // ручки, у второго игрока — по этому событию, даже если пуши он отключил.
  await publishRealtimeEventToUsers([actor.id, recipient.id], {
    type: "game_request_updated",
    matchId: occurrence.regularPair.matchId,
    searchId: occurrence.regularPair.gameSearchId,
    gameRequestId: occurrence.gameRequest?.id ?? null,
    status: occurrence.status,
    href
  });

  if (!recipient.notificationGames) {
    return;
  }

  // Время — в зоне адресата: слот переносят из чужой зоны чаще, чем кажется.
  const when = formatLocalDateTime(recipient.timezone, occurrence.scheduledAt, {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
  const courtLabel =
    occurrence.proposedCourt?.name ?? occurrence.regularPair.preferredCourt?.name ?? "Место уточняется";
  const slotLabel = `${when} · ${courtLabel}`;
  const actorLabel = playerName(actor.name);

  const content =
    change === "declined"
      ? {
          title: `${actorLabel} не сможет играть`,
          body: `${slotLabel} — предложите другое время в регулярной паре.`
        }
      : occurrence.status === RegularPairOccurrenceStatus.confirmed
        ? {
            title: "Регулярная игра подтверждена",
            body: `${slotLabel} — оба игрока подтвердили слот.`
          }
        : // Слот уже отклонён адресатом: просить у него подтверждение бессмысленно,
          // ход снова за ним, но другой — предложить время, в которое он сможет.
          occurrence.status === RegularPairOccurrenceStatus.declined
          ? {
              title: `${actorLabel} подтвердил(а) слот`,
              body: `${slotLabel} — вы отметили, что не сможете. Предложите другое время.`
            }
          : change === "proposal"
            ? {
                title: `Новое время регулярной игры от ${actorLabel}`,
                body: `${slotLabel} — подтвердите, если время подходит.`
              }
            : {
                title: `${actorLabel} подтвердил(а) слот`,
                body: `${slotLabel} — ждём вашего подтверждения.`
              };

  await sendPushToUser({
    userId: recipient.id,
    title: content.title,
    body: content.body,
    href,
    sound: recipient.notificationSound ?? true
  });
}
