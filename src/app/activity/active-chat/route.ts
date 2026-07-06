import { z } from "zod";
import { GameSearchResponseStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { clearActiveChatPresence, setActiveChatPresence } from "@/server/realtime";

const activeChatSchema = z
  .object({
    matchId: z.string().min(1).optional(),
    gameRequestId: z.string().min(1).optional(),
    searchId: z.string().min(1).optional(),
    isActive: z.boolean().default(true)
  })
  .refine((value) => Boolean(value.matchId || value.gameRequestId || value.searchId), {
    message: "Нужно указать matchId, gameRequestId или searchId"
  });

export async function POST(request: Request) {
  try {
    const user = await requireSessionUser();
    const body = activeChatSchema.parse(await request.json());
    const conversationIds: string[] = [];

    if (body.matchId) {
      const match = await prisma.match.findFirst({
        where: {
          id: body.matchId,
          OR: [{ user1Id: user.id }, { user2Id: user.id }]
        },
        select: { id: true }
      });

      if (!match) {
        return fail("Мэтч не найден", 404);
      }

      conversationIds.push(`match:${match.id}`);
    }

    if (body.gameRequestId) {
      const gameRequest = await prisma.gameRequest.findFirst({
        where: {
          id: body.gameRequestId,
          OR: [{ createdByUserId: user.id }, { matchedUserId: user.id }]
        },
        select: {
          id: true,
          matchId: true
        }
      });

      if (!gameRequest) {
        return fail("Игра не найдена", 404);
      }

      conversationIds.push(`game:${gameRequest.id}`, `match:${gameRequest.matchId}`);
    }

    if (body.searchId) {
      const gameSearch = await prisma.gameSearch.findFirst({
        where: {
          id: body.searchId,
          OR: [
            { createdByUserId: user.id },
            {
              responses: {
                some: {
                  responderUserId: user.id,
                  status: GameSearchResponseStatus.approved
                }
              }
            }
          ]
        },
        select: { id: true }
      });

      if (!gameSearch) {
        return fail("Поиск не найден", 404);
      }

      conversationIds.push(`search:${gameSearch.id}`);
    }

    const uniqueConversationIds = Array.from(new Set(conversationIds));
    await Promise.all(
      uniqueConversationIds.map((conversationId) =>
        body.isActive
          ? setActiveChatPresence(user.id, conversationId)
          : clearActiveChatPresence(user.id, conversationId)
      )
    );

    return ok({ success: true });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
