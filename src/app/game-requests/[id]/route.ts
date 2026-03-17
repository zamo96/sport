import { NextRequest } from "next/server";
import { GameRequestOutcome, GameRequestStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updateGameRequestSchema } from "@/lib/validators";
import { canTransitionGameRequest, canUpdateGameRequestOutcome } from "@/server/matching";
import { serializeGameRequest } from "@/server/serializers";

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = updateGameRequestSchema.parse(await request.json());
    const gameRequest = await prisma.gameRequest.findUnique({
      where: { id: params.id }
    });

    if (!gameRequest) {
      return fail("Предложение игры не найдено", 404);
    }

    const isCreator = gameRequest.createdByUserId === user.id;
    const isRecipient = gameRequest.matchedUserId === user.id;

    if (!isCreator && !isRecipient) {
      return fail("Нет доступа", 403);
    }

    if (body.status !== undefined) {
      if (body.status !== GameRequestStatus.canceled && !isRecipient) {
        return fail("Принять или отклонить предложение может только получатель", 403);
      }

      if (body.status === GameRequestStatus.canceled && !isCreator && !isRecipient) {
        return fail("Отменить предложение могут только участники мэтча", 403);
      }

      if (!canTransitionGameRequest(gameRequest.status, body.status)) {
        return fail("Некорректная смена статуса");
      }
    }

    if (body.outcome !== undefined) {
      if (!canUpdateGameRequestOutcome(gameRequest.status)) {
        return fail("Результат можно отметить только у принятой игры");
      }

      if (!isCreator && !isRecipient) {
        return fail("Нет доступа", 403);
      }
    }

    const updated = await prisma.$transaction(async (tx) => {
      const result = await tx.gameRequest.update({
        where: { id: params.id },
        data: {
          ...(body.status !== undefined ? { status: body.status } : {}),
          ...(body.outcome !== undefined
            ? {
                outcome: body.outcome as GameRequestOutcome | null,
                outcomeUpdatedAt: body.outcome ? new Date() : null
              }
            : {})
        },
        include: {
          proposedCourt: true
        }
      });

      await tx.match.update({
        where: { id: gameRequest.matchId },
        data: { updatedAt: new Date() }
      });

      return result;
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
