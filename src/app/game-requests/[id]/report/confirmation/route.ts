import { NextRequest } from "next/server";
import { GameReportConfirmationStatus, GameReportStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/push";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updateGameReportConfirmationSchema } from "@/lib/validators";
import { gameReportInclude, gameRequestWithReportInclude, resolveGameRequestParticipantIds } from "@/server/game-reports";
import { publishRealtimeEventToUsers } from "@/server/realtime";
import { serializeGameReport, serializeGameRequest } from "@/server/serializers";

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = updateGameReportConfirmationSchema.parse(await request.json());

    if (body.status === GameReportConfirmationStatus.pending) {
      return fail("Выбери подтверждение или спорный статус");
    }

    const report = await prisma.gameReport.findUnique({
      where: { gameRequestId: params.id },
      include: {
        gameRequest: true
      }
    });

    if (!report) {
      return fail("Фотоотчёт не найден", 404);
    }

    const participantIds = await resolveGameRequestParticipantIds(prisma, report.gameRequest);
    if (!participantIds.includes(user.id)) {
      return fail("Нет доступа", 403);
    }

    const { updatedReport, refreshedGameRequest } = await prisma.$transaction(async (tx) => {
      await tx.gameReportConfirmation.upsert({
        where: {
          reportId_userId: {
            reportId: report.id,
            userId: user.id
          }
        },
        update: {
          status: body.status
        },
        create: {
          reportId: report.id,
          userId: user.id,
          status: body.status
        }
      });

      const confirmations = await tx.gameReportConfirmation.findMany({
        where: { reportId: report.id }
      });
      const nextReportStatus = confirmations.some((confirmation) => confirmation.status === GameReportConfirmationStatus.disputed)
        ? GameReportStatus.disputed
        : confirmations.length > 0 && confirmations.every((confirmation) => confirmation.status === GameReportConfirmationStatus.confirmed)
          ? GameReportStatus.confirmed
          : GameReportStatus.pending;

      const nextReport = await tx.gameReport.update({
        where: { id: report.id },
        data: {
          status: nextReportStatus
        },
        include: gameReportInclude
      });

      await tx.chatMessage.create({
        data: {
          matchId: report.gameRequest.matchId,
          gameRequestId: report.gameRequestId,
          senderUserId: user.id,
          text:
            body.status === GameReportConfirmationStatus.confirmed
              ? "Фотоотчёт подтверждён."
              : "Фотоотчёт отмечен как спорный."
        }
      });

      const refreshed = await tx.gameRequest.findUnique({
        where: { id: report.gameRequestId },
        include: gameRequestWithReportInclude
      });

      if (!refreshed) {
        throw new Error("Игра не найдена");
      }

      return { updatedReport: nextReport, refreshedGameRequest: refreshed };
    });

    const recipientIds = participantIds.filter((participantId) => participantId !== user.id);

    await publishRealtimeEventToUsers([user.id, ...recipientIds], {
      type: "game_report_updated",
      matchId: report.gameRequest.matchId,
      gameRequestId: report.gameRequestId,
      status: updatedReport.status,
      href: `/play/games/${report.gameRequestId}`
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

    const pushBody =
      body.status === GameReportConfirmationStatus.confirmed
        ? `${user.name ?? "Игрок"} подтвердил фотоотчёт.`
        : `${user.name ?? "Игрок"} отметил фотоотчёт как спорный.`;

    await Promise.all(
      recipients.map((recipient) =>
        sendPushToUser({
          userId: recipient.id,
          title: "Обновление фотоотчёта",
          body: pushBody,
          href: `/play/games/${report.gameRequestId}`,
          sound: recipient.notificationSound ?? true
        })
      )
    );

    return ok({
      report: serializeGameReport(updatedReport),
      gameRequest: serializeGameRequest(refreshedGameRequest)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
