import { recordGameRequestMilestones } from "@/server/user-events";
import { NextRequest } from "next/server";
import { RegularPairOccurrenceConfirmationStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updateRegularPairOccurrenceSchema } from "@/lib/validators";
import {
  updateRegularPairOccurrenceConfirmation,
  updateRegularPairOccurrenceProposal
} from "@/server/regular-occurrences";
import { assertActiveCourtIds } from "@/server/court-status";
import { markCampaignConversion } from "@/server/notification-campaigns";
import {
  notifyRegularOccurrencePartner,
  type RegularOccurrenceChange
} from "@/server/regular-occurrence-notifications";

export async function PATCH(
  request: NextRequest,
  { params }: { params: { id: string; occurrenceId: string } }
) {
  try {
    const user = await requireSessionUser();
    const body = updateRegularPairOccurrenceSchema.parse(await request.json());

    const occurrence = await prisma.regularPairOccurrence.findFirst({
      include: { gameRequest: { select: { id: true } } },
      where: {
        id: params.occurrenceId,
        regularPairId: params.id,
        regularPair: {
          OR: [{ createdByUserId: user.id }, { partnerUserId: user.id }]
        }
      }
    });

    if (!occurrence) {
      return fail("Слот регулярной игры не найден", 404);
    }

    if (body.scheduledAt && new Date(body.scheduledAt).getTime() <= Date.now()) {
      return fail("Нельзя переносить слот в прошедшее время", 400);
    }

    const acceptedRequestIds: string[] = [];
    // Что сообщить второму игроку, решаем по запросу: перенос он видит как новое
    // предложение, а «смогу / не смогу» — как ответ на текущее.
    const change: RegularOccurrenceChange =
      body.status === "declined"
        ? "declined"
        : body.scheduledAt !== undefined ||
            body.proposedCourtId !== undefined ||
            body.durationMinutes !== undefined
          ? "proposal"
          : "confirmed";
    const updated = await prisma.$transaction(async (tx) => {
      if (body.proposedCourtId !== undefined) {
        await assertActiveCourtIds(tx, [body.proposedCourtId]);
      }
      let nextOccurrence = null;

      if (
        body.scheduledAt !== undefined ||
        body.proposedCourtId !== undefined ||
        body.durationMinutes !== undefined
      ) {
        nextOccurrence = await updateRegularPairOccurrenceProposal(tx, params.occurrenceId, {
          scheduledAt: body.scheduledAt ? new Date(body.scheduledAt) : undefined,
          proposedCourtId: body.proposedCourtId,
          durationMinutes: body.durationMinutes,
          proposedByUserId: user.id
        });
      }

      if (body.status) {
        const confirmed = await updateRegularPairOccurrenceConfirmation(
          tx,
          params.occurrenceId,
          user.id,
          body.status === "confirmed"
            ? RegularPairOccurrenceConfirmationStatus.confirmed
            : RegularPairOccurrenceConfirmationStatus.declined
        );
        nextOccurrence = confirmed;
        if (!occurrence.gameRequest && confirmed?.gameRequest) acceptedRequestIds.push(confirmed.gameRequest.id);
      }

      return nextOccurrence;
    });

    if (!updated) {
      return fail("Слот не найден", 404);
    }

    await recordGameRequestMilestones(acceptedRequestIds, "request_accepted", "regular");
    // Подтверждения ждут от второго игрока — значит и уведомление идёт ему.
    await notifyRegularOccurrencePartner({
      occurrenceId: params.occurrenceId,
      actorUserId: user.id,
      change
    });

    if (body.status) {
      // Целевое действие напоминания: слот наконец получил ответ.
      await markCampaignConversion(user.id, ["regular_slot_confirmation_waiting"]);
    }

    return ok({
      occurrence: {
        ...updated,
        scheduledAt: updated.scheduledAt.toISOString(),
        scheduleAnchor: updated.scheduleAnchor?.toISOString() ?? null,
        createdAt: updated.createdAt.toISOString(),
        updatedAt: updated.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "COURT_UNAVAILABLE") {
      return fail("Клуб временно недоступен", 409);
    }
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
