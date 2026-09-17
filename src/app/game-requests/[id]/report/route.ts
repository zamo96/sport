import { recordGameRequestMilestones } from "@/server/user-events";
import { NextRequest } from "next/server";
import { GameReportStatus, GameRequestOutcome, GameRequestStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameReportSchema } from "@/lib/validators";
import {
  buildAutoConfirmedGameReportConfirmations,
  gameReportInclude,
  gameRequestWithReportInclude,
  hasGameRequestEnded,
  resolveGameRequestParticipantIds
} from "@/server/game-reports";
import { publishRealtimeEventToUsers } from "@/server/realtime";
import { serializeGameReport, serializeGameRequest } from "@/server/serializers";

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = createGameReportSchema.parse(await request.json());
    const gameRequest = await prisma.gameRequest.findUnique({
      where: { id: params.id },
      include: {
        report: true,
        proposedCourt: true
      }
    });

    if (!gameRequest) {
      return fail("Игра не найдена", 404);
    }

    if (gameRequest.report) {
      return fail("Фотоотчёт по этой игре уже создан");
    }

    const participantIds = await resolveGameRequestParticipantIds(prisma, gameRequest);
    if (!participantIds.includes(user.id)) {
      return fail("Нет доступа", 403);
    }

    if (gameRequest.status !== GameRequestStatus.accepted) {
      return fail("Фотоотчёт можно добавить только к подтверждённой игре");
    }

    if (!hasGameRequestEnded(gameRequest)) {
      return fail("Фотоотчёт можно добавить после завершения игры");
    }

    if (gameRequest.outcome === GameRequestOutcome.not_played) {
      return fail("Нельзя добавить фотоотчёт к игре, которая не состоялась");
    }

    const uniquePhotoUrls = Array.from(new Set(body.photoUrls.map((url) => url.trim()).filter(Boolean))).slice(0, 5);
    if (uniquePhotoUrls.length === 0) {
      return fail("Добавь хотя бы одно фото");
    }

    const { report, refreshedGameRequest, chatMessage } = await prisma.$transaction(async (tx) => {
      const createdReport = await tx.gameReport.create({
        data: {
          gameRequestId: gameRequest.id,
          createdByUserId: user.id,
          comment: body.comment,
          visibility: body.visibility,
          status: GameReportStatus.confirmed,
          photos: {
            create: uniquePhotoUrls.map((url, index) => ({
              url,
              position: index
            }))
          },
          confirmations: {
            create: buildAutoConfirmedGameReportConfirmations(participantIds)
          }
        },
        include: gameReportInclude
      });

      await tx.gameRequest.update({
        where: { id: gameRequest.id },
        data: {
          outcome: GameRequestOutcome.played,
          outcomeUpdatedAt: new Date()
        }
      });

      const createdChatMessage = await tx.chatMessage.create({
        data: {
          matchId: gameRequest.matchId,
          gameRequestId: gameRequest.id,
          senderUserId: user.id,
          text: "Добавлен фотоотчёт по игре."
        }
      });

      await tx.match.update({
        where: { id: gameRequest.matchId },
        data: { updatedAt: new Date() }
      });

      const refreshed = await tx.gameRequest.findUnique({
        where: { id: gameRequest.id },
        include: gameRequestWithReportInclude
      });

      if (!refreshed) {
        throw new Error("Игра не найдена");
      }

      return { report: createdReport, refreshedGameRequest: refreshed, chatMessage: createdChatMessage };
    });

    if (gameRequest.outcome !== GameRequestOutcome.played) {
      await recordGameRequestMilestones([gameRequest.id], "game_played", "report");
    }
    const recipientIds = participantIds.filter((participantId) => participantId !== user.id);

    const realtimeUserIds = Array.from(new Set([user.id, ...recipientIds]));

    await publishRealtimeEventToUsers(realtimeUserIds, {
      type: "game_report_updated",
      matchId: gameRequest.matchId,
      gameRequestId: gameRequest.id,
      status: report.status,
      href: `/play/games/${gameRequest.id}`
    });

    await publishRealtimeEventToUsers(realtimeUserIds, {
      type: "chat_message_created",
      matchId: gameRequest.matchId,
      gameRequestId: gameRequest.id,
      messageId: chatMessage.id,
      href: `/play/games/${gameRequest.id}`
    });

    const recipients = await prisma.user.findMany({
      where: {
        id: {
          in: recipientIds
        },
        notificationGames: true
      },
      select: {
        id: true,
        notificationSound: true
      }
    });

    await Promise.all(
      recipients.map((recipient) =>
        sendPushToUser({
          userId: recipient.id,
          title: "Фотоотчёт по игре",
          body: `${user.name ?? "Игрок"} добавил фотоотчёт по завершённой игре.`,
          href: `/play/games/${gameRequest.id}`,
          sound: recipient.notificationSound ?? true
        })
      )
    );

    return ok({
      report: serializeGameReport(report),
      gameRequest: serializeGameRequest(refreshedGameRequest)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
