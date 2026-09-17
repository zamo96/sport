import { recordUserEvent } from "@/server/user-events";
import { NextRequest } from "next/server";
import { Prisma, type GameSearchStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchResponseSchema } from "@/lib/validators";
import { canAcceptGameSearchResponse } from "@/lib/game-search";
import { hasBlockBetweenUsers, lockActiveUsersForMutation } from "@/server/account-status";

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

    const result = await prisma.$transaction(async (tx) => {
      const lockedUserIds = await lockActiveUsersForMutation(tx, [user.id, gameSearch.createdByUserId]);
      if (!lockedUserIds.has(user.id)) {
        throw new Error("ACCOUNT_DEACTIVATED");
      }
      if (!lockedUserIds.has(gameSearch.createdByUserId)) {
        throw new Error("SEARCH_OWNER_UNAVAILABLE");
      }
      if (await hasBlockBetweenUsers(tx, user.id, gameSearch.createdByUserId)) {
        throw new Error("INTERACTION_UNAVAILABLE");
      }

      const lockedSearches = await tx.$queryRaw<Array<{
        id: string;
        createdByUserId: string;
        isActive: boolean;
        status: GameSearchStatus;
      }>>(Prisma.sql`
        SELECT "id", "createdByUserId", "isActive", "status"
        FROM "GameSearch"
        WHERE "id" = ${params.id}
        FOR UPDATE
      `);
      const lockedSearch = lockedSearches[0];

      if (!lockedSearch) {
        throw new Error("SEARCH_NOT_FOUND");
      }

      if (lockedSearch.createdByUserId !== gameSearch.createdByUserId) {
        throw new Error("SEARCH_CHANGED");
      }

      if (lockedSearch.createdByUserId === user.id) {
        throw new Error("OWN_SEARCH_RESPONSE");
      }

      if (!canAcceptGameSearchResponse(lockedSearch)) {
        throw new Error("SEARCH_INACTIVE");
      }

      const created = await tx.gameSearchResponse.upsert({
        where: {
          gameSearchId_responderUserId: {
            gameSearchId: lockedSearch.id,
            responderUserId: user.id
          }
        },
        update: {
          message: body.message,
          status: "pending"
        },
        create: {
          gameSearchId: lockedSearch.id,
          responderUserId: user.id,
          message: body.message,
          status: "pending"
        },
        include: {
          responderUser: true
        }
      });

      if (lockedSearch.status === "active") {
        const transitioned = await tx.gameSearch.updateMany({
          where: { id: lockedSearch.id, isActive: true, status: "active" },
          data: { status: "in_review" }
        });

        if (transitioned.count !== 1) {
          throw new Error("SEARCH_CHANGED");
        }
      }

      await tx.gameSearchMessage.create({
        data: {
          gameSearchId: lockedSearch.id,
          senderUserId: user.id,
          text: body.message.trim()
            ? `Откликнулся(ась) на поиск: ${body.message.trim()}`
            : "Откликнулся(ась) на поиск."
        }
      });

      return { response: created, gameSearch: lockedSearch };
    });

    const { response, gameSearch: lockedSearch } = result;

    await recordUserEvent({ userId: user.id, type: "search_response", entityType: "game_search_response", entityId: response.id });
    const owner = await prisma.user.findUnique({
      where: { id: lockedSearch.createdByUserId },
      select: {
        id: true,
        notificationGames: true,
        notificationSound: true
      }
    });

    if (owner?.notificationGames) {
      await sendPushToUser({
        userId: owner.id,
        title: `${user.name ?? "Игрок"} откликнулся на твой поиск`,
        body: body.message.trim() || "Открой поиск и реши, подтверждать ли отклик.",
        href: `/play/searches/${lockedSearch.id}`,
        sound: owner.notificationSound ?? true
      });
    }

    return ok({
      response: {
        ...response,
        createdAt: response.createdAt.toISOString(),
        updatedAt: response.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "ACCOUNT_DEACTIVATED") {
      return fail("Аккаунт деактивирован", 403);
    }

    if (getErrorMessage(error) === "SEARCH_NOT_FOUND") {
      return fail("Поиск игры не найден", 404);
    }

    if (getErrorMessage(error) === "OWN_SEARCH_RESPONSE") {
      return fail("Нельзя откликнуться на свой собственный поиск");
    }

    if (getErrorMessage(error) === "SEARCH_INACTIVE" || getErrorMessage(error) === "SEARCH_CHANGED") {
      return fail("Этот поиск уже не активен", 400);
    }

    if (getErrorMessage(error) === "SEARCH_OWNER_UNAVAILABLE") {
      return fail("Владелец поиска недоступен", 409);
    }

    if (getErrorMessage(error) === "INTERACTION_UNAVAILABLE") {
      return fail("Взаимодействие с этим пользователем недоступно", 403);
    }

    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
