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

export async function PATCH(
  request: NextRequest,
  { params }: { params: { id: string; occurrenceId: string } }
) {
  try {
    const user = await requireSessionUser();
    const body = updateRegularPairOccurrenceSchema.parse(await request.json());

    const occurrence = await prisma.regularPairOccurrence.findFirst({
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

    const updated = await prisma.$transaction(async (tx) => {
      let nextOccurrence = null;

      if (
        body.scheduledAt !== undefined ||
        body.proposedCourtId !== undefined ||
        body.durationMinutes !== undefined
      ) {
        nextOccurrence = await updateRegularPairOccurrenceProposal(tx, params.occurrenceId, {
          scheduledAt: body.scheduledAt ? new Date(body.scheduledAt) : undefined,
          proposedCourtId: body.proposedCourtId,
          durationMinutes: body.durationMinutes
        });
      }

      if (body.status) {
        nextOccurrence = await updateRegularPairOccurrenceConfirmation(
          tx,
          params.occurrenceId,
          user.id,
          body.status === "confirmed"
            ? RegularPairOccurrenceConfirmationStatus.confirmed
            : RegularPairOccurrenceConfirmationStatus.declined
        );
      }

      return nextOccurrence;
    });

    if (!updated) {
      return fail("Слот не найден", 404);
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
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
