import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { messageSchema } from "@/lib/validators";

async function getMatchForUser(matchId: string, userId: string) {
  return prisma.match.findFirst({
    where: {
      id: matchId,
      OR: [{ user1Id: userId }, { user2Id: userId }]
    }
  });
}

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const match = await getMatchForUser(params.id, user.id);

    if (!match) {
      return fail("Мэтч не найден", 404);
    }

    const messages = await prisma.chatMessage.findMany({
      where: {
        matchId: match.id
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
    const body = messageSchema.parse(await request.json());
    const match = await getMatchForUser(params.id, user.id);

    if (!match) {
      return fail("Мэтч не найден", 404);
    }

    const message = await prisma.$transaction(async (tx) => {
      const created = await tx.chatMessage.create({
        data: {
          matchId: match.id,
          senderUserId: user.id,
          text: body.text
        },
        include: {
          senderUser: true
        }
      });

      await tx.match.update({
        where: { id: match.id },
        data: { updatedAt: new Date() }
      });

      return created;
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
