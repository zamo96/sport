import { NextRequest } from "next/server";
import { z } from "zod";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { runGameRequestMaintenance } from "@/server/game-request-maintenance";
import { ensureMatchForUsers } from "@/server/matching";
import { otherUserFromMatch } from "@/server/serializers";
import {
  chatMessageAttachmentsInclude,
  serializeChatMessage
} from "@/server/chat-media";

const createMatchSchema = z.object({
  userId: z.string().min(1)
});

export async function GET() {
  try {
    const user = await requireSessionUser();
    await runGameRequestMaintenance({ sendReminders: false });
    const matches = await prisma.match.findMany({
      where: {
        OR: [{ user1Id: user.id }, { user2Id: user.id }]
      },
      include: {
        user1: true,
        user2: true,
        messages: {
          include: chatMessageAttachmentsInclude,
          where: {
            gameRequestId: null
          },
          orderBy: { createdAt: "desc" },
          take: 1
        },
        gameRequests: {
          include: {
            proposedCourt: true
          },
          orderBy: { createdAt: "desc" },
          take: 1
        }
      },
      orderBy: {
        updatedAt: "desc"
      }
    });

    return ok({
      matches: matches.map((match) => ({
        id: match.id,
        status: match.status,
        createdAt: match.createdAt.toISOString(),
        otherUser: otherUserFromMatch(match, user.id),
        lastMessage: match.messages[0]
          ? serializeChatMessage(match.messages[0])
          : null,
        latestGameRequest: match.gameRequests[0]
          ? {
              ...match.gameRequests[0],
              proposedDatetime: match.gameRequests[0].proposedDatetime.toISOString(),
              durationMinutes: match.gameRequests[0].durationMinutes ?? null,
              outcomeUpdatedAt: match.gameRequests[0].outcomeUpdatedAt?.toISOString() ?? null,
              createdAt: match.gameRequests[0].createdAt.toISOString(),
              updatedAt: match.gameRequests[0].updatedAt.toISOString()
            }
          : null
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = createMatchSchema.parse(await request.json());

    if (body.userId === user.id) {
      return fail("Нельзя создать мэтч с собой");
    }

    const targetUser = await prisma.user.findUnique({
      where: { id: body.userId }
    });

    if (!targetUser) {
      return fail("Игрок не найден", 404);
    }

    const existingBlock = await prisma.block.findFirst({
      where: {
        OR: [
          { blockerUserId: user.id, blockedUserId: body.userId },
          { blockerUserId: body.userId, blockedUserId: user.id }
        ]
      }
    });

    if (existingBlock) {
      return fail("Взаимодействие с этим пользователем недоступно");
    }

    const match = await prisma.$transaction(async (tx) => {
      const ensured = await ensureMatchForUsers(tx, user.id, body.userId);
      return tx.match.findUnique({
        where: { id: ensured.id },
        include: {
          user1: true,
          user2: true,
          messages: {
            include: chatMessageAttachmentsInclude,
            where: {
              gameRequestId: null
            },
            orderBy: { createdAt: "desc" },
            take: 1
          },
          gameRequests: {
            include: {
              proposedCourt: true
            },
            orderBy: { createdAt: "desc" },
            take: 1
          }
        }
      });
    });

    if (!match) {
      return fail("Мэтч не найден", 404);
    }

    return ok({
      match: {
        id: match.id,
        status: match.status,
        createdAt: match.createdAt.toISOString(),
        otherUser: otherUserFromMatch(match, user.id),
        lastMessage: match.messages[0]
          ? serializeChatMessage(match.messages[0])
          : null,
        latestGameRequest: match.gameRequests[0]
          ? {
              ...match.gameRequests[0],
              proposedDatetime: match.gameRequests[0].proposedDatetime.toISOString(),
              durationMinutes: match.gameRequests[0].durationMinutes ?? null,
              outcomeUpdatedAt: match.gameRequests[0].outcomeUpdatedAt?.toISOString() ?? null,
              createdAt: match.gameRequests[0].createdAt.toISOString(),
              updatedAt: match.gameRequests[0].updatedAt.toISOString()
            }
          : null
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
