import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchResponseSchema } from "@/lib/validators";

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = createGameSearchResponseSchema.parse(await request.json());

    const gameSearch = await prisma.gameSearch.findUnique({
      where: {
        id: params.id
      }
    });

    if (!gameSearch) {
      return fail("Поиск игры не найден", 404);
    }

    if (gameSearch.createdByUserId === user.id) {
      return fail("Нельзя откликнуться на свой собственный поиск");
    }

    if (!gameSearch.isActive || gameSearch.status === "matched" || gameSearch.status === "closed") {
      return fail("Этот поиск уже не активен", 400);
    }

    const response = await prisma.$transaction(async (tx) => {
      const created = await tx.gameSearchResponse.upsert({
        where: {
          gameSearchId_responderUserId: {
            gameSearchId: gameSearch.id,
            responderUserId: user.id
          }
        },
        update: {
          message: body.message,
          status: "pending"
        },
        create: {
          gameSearchId: gameSearch.id,
          responderUserId: user.id,
          message: body.message,
          status: "pending"
        },
        include: {
          responderUser: true
        }
      });

      await tx.gameSearch.update({
        where: { id: gameSearch.id },
        data: {
          status: "in_review"
        }
      });

      await tx.gameSearchMessage.create({
        data: {
          gameSearchId: gameSearch.id,
          senderUserId: user.id,
          text: body.message.trim()
            ? `Откликнулся(ась) на поиск: ${body.message.trim()}`
            : "Откликнулся(ась) на поиск."
        }
      });

      return created;
    });

    return ok({
      response: {
        ...response,
        createdAt: response.createdAt.toISOString(),
        updatedAt: response.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
