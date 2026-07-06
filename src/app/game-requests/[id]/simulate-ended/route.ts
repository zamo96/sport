import { GameRequestStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import {
  buildCompletedGameSimulationDatetime,
  gameRequestWithReportInclude,
  resolveGameRequestParticipantIds
} from "@/server/game-reports";
import { serializeGameRequest } from "@/server/serializers";

function isSimulationEnabled() {
  return process.env.NODE_ENV !== "production" || process.env.ENABLE_GAME_COMPLETION_SIMULATION === "true";
}

export async function POST(_: Request, { params }: { params: { id: string } }) {
  try {
    if (!isSimulationEnabled()) {
      return fail("Симуляция доступна только в demo/dev режиме", 403);
    }

    const user = await requireSessionUser();
    const gameRequest = await prisma.gameRequest.findUnique({
      where: { id: params.id }
    });

    if (!gameRequest) {
      return fail("Игра не найдена", 404);
    }

    const participantIds = await resolveGameRequestParticipantIds(prisma, gameRequest);
    if (!participantIds.includes(user.id)) {
      return fail("Нет доступа", 403);
    }

    if (gameRequest.status !== GameRequestStatus.accepted) {
      return fail("Симулировать завершение можно только для подтверждённой игры");
    }

    const proposedDatetime = buildCompletedGameSimulationDatetime(gameRequest.durationMinutes);

    const updated = await prisma.$transaction(async (tx) => {
      const refreshed = await tx.gameRequest.update({
        where: { id: gameRequest.id },
        data: {
          proposedDatetime,
          outcome: null,
          outcomeUpdatedAt: null
        },
        include: gameRequestWithReportInclude
      });

      await tx.chatMessage.create({
        data: {
          matchId: gameRequest.matchId,
          gameRequestId: gameRequest.id,
          senderUserId: user.id,
          text: "Симуляция: игра перенесена в прошлое, теперь можно проверить фотоотчёт."
        }
      });

      await tx.match.update({
        where: { id: gameRequest.matchId },
        data: { updatedAt: new Date() }
      });

      return refreshed;
    });

    return ok({
      gameRequest: serializeGameRequest(updated)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
