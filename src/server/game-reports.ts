import { GameReportConfirmationStatus, GameRequest, Prisma } from "@prisma/client";

export const gameReportInclude = {
  createdByUser: true,
  photos: {
    orderBy: {
      position: "asc" as const
    }
  },
  confirmations: {
    include: {
      user: true
    }
  }
};

export const gameRequestWithReportInclude = {
  proposedCourt: true,
  report: {
    include: gameReportInclude
  }
};

type GameRequestIdentity = Pick<GameRequest, "id" | "sharedRootId" | "createdByUserId" | "matchedUserId">;
type PrismaClientLike = Pick<Prisma.TransactionClient, "gameRequest">;

export async function resolveGameRequestParticipantIds(tx: PrismaClientLike, gameRequest: GameRequestIdentity) {
  const rootRequestId = gameRequest.sharedRootId ?? gameRequest.id;
  const relatedRequests = await tx.gameRequest.findMany({
    where: {
      OR: [{ id: rootRequestId }, { sharedRootId: rootRequestId }]
    },
    select: {
      createdByUserId: true,
      matchedUserId: true
    }
  });

  const candidateIds = relatedRequests.length > 0
    ? relatedRequests.flatMap((request) => [request.createdByUserId, request.matchedUserId])
    : [gameRequest.createdByUserId, gameRequest.matchedUserId];

  return Array.from(new Set(candidateIds.filter(Boolean)));
}

export function hasGameRequestEnded(gameRequest: Pick<GameRequest, "proposedDatetime" | "durationMinutes">, now = new Date()) {
  const durationMinutes = gameRequest.durationMinutes ?? 90;
  const finishedAt = gameRequest.proposedDatetime.getTime() + durationMinutes * 60 * 1000;
  return now.getTime() >= finishedAt;
}

export function buildCompletedGameSimulationDatetime(durationMinutes: number | null | undefined, now = new Date()) {
  const resolvedDurationMinutes = durationMinutes ?? 90;
  return new Date(now.getTime() - (resolvedDurationMinutes + 5) * 60 * 1000);
}

export function buildAutoConfirmedGameReportConfirmations(participantIds: string[]) {
  return participantIds.map((participantId) => ({
    userId: participantId,
    status: GameReportConfirmationStatus.confirmed
  }));
}
