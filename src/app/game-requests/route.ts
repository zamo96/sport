import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameRequestSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = createGameRequestSchema.parse(await request.json());
    const match = await prisma.match.findFirst({
      where: {
        id: body.matchId,
        OR: [{ user1Id: user.id }, { user2Id: user.id }]
      }
    });

    if (!match) {
      return fail("Мэтч не найден", 404);
    }

    const matchedUserId = match.user1Id === user.id ? match.user2Id : match.user1Id;

    const gameRequest = await prisma.$transaction(async (tx) => {
      const created = await tx.gameRequest.create({
        data: {
          matchId: match.id,
          createdByUserId: user.id,
          matchedUserId,
          proposedCourtId: body.proposedCourtId,
          proposedDatetime: new Date(body.proposedDatetime),
          levelRangeMin: body.levelRangeMin ?? null,
          levelRangeMax: body.levelRangeMax ?? null,
          sport: body.sport,
          format: body.format,
          comment: body.comment
        },
        include: {
          proposedCourt: true
        }
      });

      await tx.match.update({
        where: { id: match.id },
        data: { updatedAt: new Date() }
      });

      return created;
    });

    return ok({
      gameRequest: {
        ...gameRequest,
        proposedDatetime: gameRequest.proposedDatetime.toISOString(),
        createdAt: gameRequest.createdAt.toISOString(),
        updatedAt: gameRequest.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
