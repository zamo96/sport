import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updateGameSearchSchema } from "@/lib/validators";

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = updateGameSearchSchema.parse(await request.json());

    const gameSearch = await prisma.gameSearch.findFirst({
      where: {
        id: params.id,
        createdByUserId: user.id
      }
    });

    if (!gameSearch) {
      return fail("Поиск игры не найден", 404);
    }

    const updated = await prisma.gameSearch.update({
      where: { id: gameSearch.id },
      data: {
        isActive: body.isActive,
        status: body.isActive ? "active" : "closed"
      },
      include: {
        preferredCourt: true,
        responses: {
          include: {
            responderUser: true
          }
        }
      }
    });

    return ok({
      gameSearch: {
        ...updated,
        createdAt: updated.createdAt.toISOString(),
        updatedAt: updated.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();

    const gameSearch = await prisma.gameSearch.findFirst({
      where: {
        id: params.id,
        OR: [
          { createdByUserId: user.id },
          {
            responses: {
              some: {
                responderUserId: user.id
              }
            }
          }
        ]
      },
      include: {
        preferredCourt: true,
        createdByUser: true,
        responses: {
          include: {
            responderUser: true
          },
          orderBy: [
            { status: "asc" },
            { createdAt: "asc" }
          ]
        }
      }
    });

    if (!gameSearch) {
      return fail("Поиск игры не найден", 404);
    }

    return ok({
      gameSearch: {
        ...gameSearch,
        createdAt: gameSearch.createdAt.toISOString(),
        updatedAt: gameSearch.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
