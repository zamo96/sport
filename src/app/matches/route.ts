import { NextRequest } from "next/server";
import { z } from "zod";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { runGameRequestMaintenance } from "@/server/game-request-maintenance";
import { ensureMatchForUsers } from "@/server/matching";
import { lockActiveUsersForMutation } from "@/server/account-status";
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
        OR: [{ user1Id: user.id }, { user2Id: user.id }],
        user1: {
          blockedUsers: { none: { blockedUserId: user.id } },
          blockingUsers: { none: { blockerUserId: user.id } }
        },
        user2: {
          blockedUsers: { none: { blockedUserId: user.id } },
          blockingUsers: { none: { blockerUserId: user.id } }
        }
      },
      include: {
        user1: { include: { location: { include: { serviceArea: true } } } },
        user2: { include: { location: { include: { serviceArea: true } } } },
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

    const match = await prisma.$transaction(async (tx) => {
      const lockedUserIds = await lockActiveUsersForMutation(tx, [user.id, body.userId]);
      if (!lockedUserIds.has(user.id)) {
        throw new Error("ACCOUNT_DEACTIVATED");
      }
      if (!lockedUserIds.has(body.userId)) {
        throw new Error("PLAYER_UNAVAILABLE");
      }

      const existingBlock = await tx.block.findFirst({
        where: {
          OR: [
            { blockerUserId: user.id, blockedUserId: body.userId },
            { blockerUserId: body.userId, blockedUserId: user.id }
          ]
        }
      });

      if (existingBlock) {
        throw new Error("INTERACTION_UNAVAILABLE");
      }

      const ensured = await ensureMatchForUsers(tx, user.id, body.userId);
      return tx.match.findUnique({
        where: { id: ensured.id },
        include: {
          user1: { include: { location: { include: { serviceArea: true } } } },
          user2: { include: { location: { include: { serviceArea: true } } } },
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
    if (getErrorMessage(error) === "ACCOUNT_DEACTIVATED") {
      return fail("Аккаунт деактивирован", 403);
    }

    if (getErrorMessage(error) === "PLAYER_UNAVAILABLE") {
      return fail("Игрок не найден", 404);
    }

    if (getErrorMessage(error) === "INTERACTION_UNAVAILABLE") {
      return fail("Взаимодействие с этим пользователем недоступно");
    }

    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
