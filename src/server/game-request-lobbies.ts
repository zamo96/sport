import { GameRequest, GameRequestStatus, GameSearchResponseStatus, GameSearchStatus, GameSearchType, Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";

type DbClient = typeof prisma | Prisma.TransactionClient;

type GroupGameRequest = Pick<
  GameRequest,
  | "id"
  | "sharedRootId"
  | "createdByUserId"
  | "matchedUserId"
  | "proposedCourtId"
  | "proposedDatetime"
  | "durationMinutes"
  | "sport"
  | "format"
  | "comment"
  | "status"
>;

export async function ensureGroupSearchLobby(
  db: DbClient,
  requests: GroupGameRequest[],
  options: { senderUserId?: string; createIntroMessage?: boolean } = {}
) {
  const uniqueRequests = dedupeRequests(requests);
  if (uniqueRequests.length <= 1) {
    return null;
  }

  const primaryRequest = selectPrimaryGroupRequest(uniqueRequests);
  const nextStatus = resolveSearchStatus(uniqueRequests);
  const existing = await db.gameSearch.findFirst({
    where: {
      createdByUserId: primaryRequest.createdByUserId,
      scheduledAt: primaryRequest.proposedDatetime,
      scheduledCourtId: primaryRequest.proposedCourtId,
      sport: primaryRequest.sport,
      format: primaryRequest.format,
      playersNeeded: {
        gt: 1
      }
    },
    select: {
      id: true
    },
    orderBy: {
      updatedAt: "desc"
    }
  });

  const lobbyData = {
    preferredCourtId: primaryRequest.proposedCourtId,
    scheduledCourtId: primaryRequest.proposedCourtId,
    preferredDays: [] as Prisma.InputJsonValue,
    preferredTimeRanges: [] as Prisma.InputJsonValue,
    searchType: GameSearchType.regular,
    durationMinutes: primaryRequest.durationMinutes ?? null,
    scheduledAt: primaryRequest.proposedDatetime,
    scheduledDurationMinutes: primaryRequest.durationMinutes ?? null,
    hasCourtBooked: true,
    sport: primaryRequest.sport,
    format: primaryRequest.format,
    playersNeeded: uniqueRequests.length,
    comment: primaryRequest.comment?.trim() || "Общий чат команды по назначенной игре.",
    status: nextStatus,
    isActive: nextStatus !== GameSearchStatus.matched && nextStatus !== GameSearchStatus.closed
  };

  const lobby = existing
    ? await db.gameSearch.update({
        where: { id: existing.id },
        data: lobbyData,
        select: { id: true }
      })
    : await db.gameSearch.create({
        data: {
          createdByUserId: primaryRequest.createdByUserId,
          ...lobbyData
        },
        select: { id: true }
      });

  await Promise.all(
    uniqueRequests.map((request) =>
      db.gameSearchResponse.upsert({
        where: {
          gameSearchId_responderUserId: {
            gameSearchId: lobby.id,
            responderUserId: request.matchedUserId
          }
        },
        update: {
          status: mapGameRequestStatusToSearchResponseStatus(request.status)
        },
        create: {
          gameSearchId: lobby.id,
          responderUserId: request.matchedUserId,
          status: mapGameRequestStatusToSearchResponseStatus(request.status),
          message: "Участник общей игры."
        }
      })
    )
  );

  if (!existing && options.createIntroMessage && options.senderUserId) {
    await db.gameSearchMessage.create({
      data: {
        gameSearchId: lobby.id,
        senderUserId: options.senderUserId,
        text: "Создан общий чат команды для этой игры."
      }
    });
  }

  return lobby.id;
}

function dedupeRequests<T extends GroupGameRequest>(requests: T[]) {
  const seen = new Set<string>();
  return requests.filter((request) => {
    if (seen.has(request.id)) {
      return false;
    }
    seen.add(request.id);
    return true;
  });
}

function selectPrimaryGroupRequest<T extends GroupGameRequest>(requests: T[]) {
  return requests.find((request) => !request.sharedRootId) ?? requests[0];
}

function mapGameRequestStatusToSearchResponseStatus(status: GameRequestStatus) {
  switch (status) {
    case GameRequestStatus.accepted:
      return GameSearchResponseStatus.approved;
    case GameRequestStatus.declined:
    case GameRequestStatus.canceled:
      return GameSearchResponseStatus.rejected;
    case GameRequestStatus.pending:
    default:
      return GameSearchResponseStatus.pending;
  }
}

function resolveSearchStatus(requests: GroupGameRequest[]) {
  const approvedCount = requests.filter((request) => request.status === GameRequestStatus.accepted).length;
  const pendingCount = requests.filter((request) => request.status === GameRequestStatus.pending).length;
  const rejectedCount = requests.filter(
    (request) => request.status === GameRequestStatus.declined || request.status === GameRequestStatus.canceled
  ).length;

  if (rejectedCount === requests.length) {
    return GameSearchStatus.closed;
  }

  if (approvedCount >= requests.length) {
    return GameSearchStatus.matched;
  }

  if (approvedCount > 0 || pendingCount > 0) {
    return GameSearchStatus.in_review;
  }

  return GameSearchStatus.active;
}
