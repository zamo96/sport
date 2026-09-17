import { recordUserEvent, recordUserEventsOnce } from "@/server/user-events";
import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { sendPushToUser } from "@/lib/push";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { swipeSchema } from "@/lib/validators";
import { createSwipeAndMaybeMatch } from "@/server/matching";
import { isProfileReadyForMatching } from "@/lib/scoring";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { translateServer } from "@/lib/i18n/server";
import { publishRealtimeEventToUsers } from "@/server/realtime";
import { lockActiveUsersForMutation } from "@/server/account-status";

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = swipeSchema.parse(await request.json());

    if (body.toUserId === user.id) {
      return fail("Нельзя свайпнуть самого себя");
    }

    // Незавершённый профиль не проходит `scoreCandidate`, поэтому его лайк
    // порождал уведомление, за которым в «Хотят с тобой» никого нет.
    if ((body.action === "like" || body.action === "superlike") && !isProfileReadyForMatching(user)) {
      return fail(
        translateServer(getServerRequestLocale(request), "profile.error.incompleteForMatching"),
        403,
        "PROFILE_INCOMPLETE"
      );
    }

    const { targetUser, result, matchCreated } = await prisma.$transaction(async (tx) => {
      const lockedUserIds = await lockActiveUsersForMutation(tx, [user.id, body.toUserId]);
      if (!lockedUserIds.has(user.id)) {
        throw new Error("ACCOUNT_DEACTIVATED");
      }
      if (!lockedUserIds.has(body.toUserId)) {
        throw new Error("PLAYER_UNAVAILABLE");
      }

      const target = await tx.user.findUniqueOrThrow({ where: { id: body.toUserId } });
      const existingBlock = await tx.block.findFirst({
        where: {
          OR: [
            { blockerUserId: user.id, blockedUserId: body.toUserId },
            { blockerUserId: body.toUserId, blockedUserId: user.id }
          ]
        }
      });

      if (existingBlock) {
        throw new Error("INTERACTION_UNAVAILABLE");
      }

      const [user1Id, user2Id] = [user.id, body.toUserId].sort();
      const previousMatch = await tx.match.findUnique({ where: { user1Id_user2Id: { user1Id, user2Id } }, select: { id: true } });
      const result = await createSwipeAndMaybeMatch(tx, user.id, body.toUserId, body.action);
      return { targetUser: target, result, matchCreated: Boolean(result.match && !previousMatch) };
    });

    await recordUserEvent({ userId: user.id, type: "swipe", entityType: "user", entityId: targetUser.id, context: { action: body.action } });
    if (result.match && matchCreated) {
      await recordUserEventsOnce([user.id, targetUser.id].map((userId) => ({ userId, type: "match_created", entityType: "match", entityId: result.match!.id })));
    }
    if (result.match && targetUser.notificationMatches) {
      await sendPushToUser({
        userId: targetUser.id,
        title: "У тебя новый мэтч",
        body: `${user.name ?? "Игрок"} ответил взаимностью. Можно открыть чат и договориться об игре.`,
        href: `/inbox/${result.match.id}`,
        sound: targetUser.notificationSound ?? true
      });
    }

    if (result.match) {
      await publishRealtimeEventToUsers([user.id, targetUser.id], {
        type: "match_created",
        matchId: result.match.id,
        href: `/inbox/${result.match.id}`
      });
    } else if ((body.action === "like" || body.action === "superlike") && targetUser.notificationMatches) {
      await sendPushToUser({
        userId: targetUser.id,
        title: `${user.name ?? "Игрок"} хочет с тобой сыграть`,
        body: "Открой вкладку «Хотят с тобой поиграть», чтобы ответить.",
        href: `/discover?view=likes&highlight=${user.id}`,
        sound: targetUser.notificationSound ?? true
      });
    }

    return ok({
      swipe: result.swipe,
      match: result.match
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
