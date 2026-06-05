import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { ensureGroupSearchLobby } from "@/server/game-request-lobbies";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";
import { serializeGameRequest, serializeUserPreview } from "@/server/serializers";

type RequestWithRelations = Awaited<ReturnType<typeof loadGameRequests>>[number];
type ChildRequest = RequestWithRelations["sharedInvites"][number];
type SerializedGameRequest = ReturnType<typeof serializeRequest>;
type SerializedRegularOccurrence = ReturnType<typeof serializeRegularOccurrence>;

export async function GET() {
  try {
    const user = await requireSessionUser();
    const pairIds = await prisma.regularPair.findMany({
      where: {
        OR: [{ createdByUserId: user.id }, { partnerUserId: user.id }]
      },
      select: {
        id: true
      }
    });
    await Promise.all(pairIds.map((pair) => syncRegularPairOccurrences(prisma, pair.id)));
    const gameRequests = await loadGameRequests(user.id);
    const regularOccurrences = await loadConfirmedRegularOccurrences(user.id);
    const groupedRequests = buildRequestGroups(gameRequests);
    const searchLobbyIdsByRootRequestId = await resolveSearchLobbyIds(groupedRequests);

    const grouped: Array<SerializedGameRequest | SerializedRegularOccurrence> = gameRequests
      .filter((gameRequest) => {
        if (!gameRequest.sharedRootId) {
          return true;
        }

        return gameRequest.matchedUserId === user.id;
      })
      .map((gameRequest) => {
        const rootRequestId = gameRequest.sharedRootId ?? gameRequest.id;
        const groupRequests = groupedRequests.get(rootRequestId) ?? [gameRequest];
        const groupParticipants = serializeGroupParticipants(groupRequests);

        if (gameRequest.sharedRootId || gameRequest.createdByUserId !== user.id) {
          return serializeRequest(gameRequest, {
            rootRequestId,
            searchLobbyId: searchLobbyIdsByRootRequestId.get(rootRequestId) ?? null,
            participants: groupParticipants
          });
        }

        const primaryRequest = selectPrimaryRequest(groupRequests);

        return serializeRequest(primaryRequest, {
          rootRequestId,
          searchLobbyId: searchLobbyIdsByRootRequestId.get(rootRequestId) ?? null,
          participants: groupParticipants,
          invitees: groupRequests
            .filter((request) => request.id !== primaryRequest.id)
            .map((invite) => ({
            id: invite.id,
            matchId: invite.matchId,
            status: invite.status,
            user: serializeUserPreview(invite.matchedUser)
          }))
        });
      });

    grouped
      .push(...regularOccurrences.map(serializeRegularOccurrence));

    grouped
      .sort((left, right) => right.createdAt.getTime() - left.createdAt.getTime());

    return ok({
      gameRequests: grouped
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

async function resolveSearchLobbyIds(groups: Map<string, Array<RequestWithRelations | ChildRequest>>) {
  const result = new Map<string, string>();

  const roots = Array.from(groups.entries())
    .map(([rootId, requests]) => ({ rootId, requests }))
    .filter(({ requests }) => requests.length > 1);

  await Promise.all(
    roots.map(async ({ rootId, requests }) => {
      const lobbyId = await ensureGroupSearchLobby(prisma, requests);

      if (lobbyId) {
        result.set(rootId, lobbyId);
      }
    })
  );

  return result;
}

function buildRequestGroups(gameRequests: RequestWithRelations[]) {
  const byId = new Map<string, RequestWithRelations | ChildRequest>();
  for (const request of gameRequests) {
    byId.set(request.id, request);
    for (const invite of request.sharedInvites) {
      byId.set(invite.id, invite);
    }
  }

  const groups = new Map<string, Array<RequestWithRelations | ChildRequest>>();
  for (const request of byId.values()) {
    const rootId = request.sharedRootId ?? request.id;
    const bucket = groups.get(rootId) ?? [];
    bucket.push(request);
    groups.set(rootId, bucket);
  }

  return groups;
}

async function loadGameRequests(userId: string) {
  return prisma.gameRequest.findMany({
    where: {
      OR: [{ createdByUserId: userId }, { matchedUserId: userId }]
    },
    include: {
      proposedCourt: true,
      createdByUser: true,
      matchedUser: true,
      match: {
        include: {
          user1: true,
          user2: true
        }
      },
      sharedInvites: {
        include: {
          proposedCourt: true,
          createdByUser: true,
          matchedUser: true,
          match: {
            include: {
              user1: true,
              user2: true
            }
          }
        },
        orderBy: {
          createdAt: "desc"
        }
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });
}

async function loadConfirmedRegularOccurrences(userId: string) {
  return prisma.regularPairOccurrence.findMany({
    where: {
      status: "confirmed",
      gameRequest: null,
      regularPair: {
        OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
      }
    },
    include: {
      proposedCourt: true,
      gameRequest: true,
      confirmations: {
        include: {
          user: true
        }
      },
      regularPair: {
        include: {
          preferredCourt: true,
          createdByUser: true,
          partnerUser: true,
          match: {
            include: {
              user1: true,
              user2: true
            }
          }
        }
      }
    },
    orderBy: {
      scheduledAt: "desc"
    }
  });
}

function selectPrimaryRequest(requests: Array<RequestWithRelations | ChildRequest>) {
  const accepted = requests.find((request) => request.status === "accepted");
  if (accepted) {
    return accepted;
  }

  const pending = requests.find((request) => request.status === "pending");
  if (pending) {
    return pending;
  }

  return requests[0];
}

function serializeRequest(
  gameRequest: RequestWithRelations | ChildRequest,
  options?: {
    rootRequestId?: string;
    searchLobbyId?: string | null;
    participants?: ReturnType<typeof serializeUserPreview>[];
    invitees?: Array<{
      id: string;
      matchId: string;
      status: string;
      user: ReturnType<typeof serializeUserPreview>;
    }>;
  }
) {
  return {
    ...serializeGameRequest(gameRequest),
    rootRequestId: options?.rootRequestId ?? gameRequest.sharedRootId ?? gameRequest.id,
    searchLobbyId: options?.searchLobbyId ?? null,
    createdByUser: serializeUserPreview(gameRequest.createdByUser),
    matchedUser: serializeUserPreview(gameRequest.matchedUser),
    participants:
      options?.participants ?? [serializeUserPreview(gameRequest.match.user1), serializeUserPreview(gameRequest.match.user2)],
    invitees: options?.invitees ?? []
  };
}

function serializeGroupParticipants(requests: Array<RequestWithRelations | ChildRequest>) {
  const seen = new Set<string>();
  const participants: ReturnType<typeof serializeUserPreview>[] = [];

  for (const request of requests) {
    const candidateUsers = [request.createdByUser, request.matchedUser];
    for (const candidate of candidateUsers) {
      if (!candidate.id || seen.has(candidate.id)) {
        continue;
      }
      seen.add(candidate.id);
      participants.push(serializeUserPreview(candidate));
    }
  }

  return participants;
}

function serializeRegularOccurrence(
  occurrence: Awaited<ReturnType<typeof loadConfirmedRegularOccurrences>>[number]
) {
  const pair = occurrence.regularPair;
  return {
    id: occurrence.id,
    matchId: pair.matchId,
    rootRequestId: occurrence.id,
    createdByUserId: pair.createdByUserId,
    matchedUserId: pair.partnerUserId,
    status: "accepted",
    proposedDatetime: occurrence.scheduledAt.toISOString(),
    durationMinutes: occurrence.durationMinutes ?? 90,
    sport: occurrence.sport,
    format: occurrence.format,
    comment: pair.comment ?? "Регулярная игра подтверждена обеими сторонами.",
    outcome: null,
    outcomeUpdatedAt: null,
    createdAt: occurrence.createdAt,
    updatedAt: occurrence.updatedAt,
    proposedCourt: occurrence.proposedCourt ?? pair.preferredCourt,
    createdByUser: serializeUserPreview(pair.createdByUser),
    matchedUser: serializeUserPreview(pair.partnerUser),
    participants: [serializeUserPreview(pair.match.user1), serializeUserPreview(pair.match.user2)],
    invitees: [],
    sourceType: "regular_occurrence",
    regularPairId: pair.id
  };
}
