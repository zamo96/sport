import { NextRequest } from "next/server";
import { GameSearchResponseStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchMessageSchema } from "@/lib/validators";

async function canAccessSearch(userId: string, gameSearchId: string) {
  return prisma.gameSearch.findFirst({
    where: {
      id: gameSearchId,
      OR: [
        { createdByUserId: userId },
        {
          responses: {
            some: {
              responderUserId: userId,
              status: {
                in: [GameSearchResponseStatus.approved, GameSearchResponseStatus.pending]
              }
            }
          }
        }
      ]
    },
    select: { id: true }
  });
}

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const allowed = await canAccessSearch(user.id, params.id);

    if (!allowed) {
      return fail("Нет доступа", 403);
    }

    const messages = await prisma.gameSearchMessage.findMany({
      where: {
        gameSearchId: params.id
      },
      include: {
        senderUser: true
      },
      orderBy: {
        createdAt: "asc"
      }
    });

    return ok({
      messages: messages.map((message) => ({
        ...message,
        createdAt: message.createdAt.toISOString()
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const allowed = await canAccessSearch(user.id, params.id);

    if (!allowed) {
      return fail("Нет доступа", 403);
    }

    const body = createGameSearchMessageSchema.parse(await request.json());

    const message = await prisma.gameSearchMessage.create({
      data: {
        gameSearchId: params.id,
        senderUserId: user.id,
        text: body.text
      },
      include: {
        senderUser: true
      }
    });

    return ok({
      message: {
        ...message,
        createdAt: message.createdAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
