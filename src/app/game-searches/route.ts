import { NextRequest } from "next/server";
import { Prisma } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { resolveHotSearchStartAt, resolveSearchDays } from "@/lib/game-search";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { hasExplicitSportProfile } from "@/lib/sport-levels";
import { isRouteSport } from "@/lib/sport-semantics";
import { createGameSearchSchema } from "@/lib/validators";
import { assertActiveCourtIds } from "@/server/court-status";

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = createGameSearchSchema.parse(await request.json());

    const hasSportProfile = hasExplicitSportProfile(user.preferredSports, user.sportLevels, body.sport);

    if (!hasSportProfile && !body.selfLevelUnknown && body.selfLevel == null) {
      return fail("Укажи свой уровень по этому виду спорта или выбери «Не знаю»");
    }

    const explicitHotStartsAt = body.hotStartsAt ? new Date(body.hotStartsAt) : null;
    const hotStartsAt =
      body.searchType === "hot"
        ? explicitHotStartsAt ?? (body.hotWindow && body.hotStartTime ? resolveHotSearchStartAt(body.hotWindow, body.hotStartTime) : null)
        : null;
    const preferredDays = resolveSearchDays(body.searchType, body.preferredDays, explicitHotStartsAt ? null : body.hotWindow, hotStartsAt);

    if (body.searchType === "hot" && !hotStartsAt) {
      return fail("Не удалось определить время начала горячего поиска");
    }

    if (body.searchType === "hot" && hotStartsAt && hotStartsAt.getTime() <= Date.now()) {
      return fail("Для горячего поиска выбери время позже текущего");
    }

    const gameSearch = await prisma.$transaction(async (tx) => {
      const activeAccount = await tx.user.updateMany({
        where: { id: user.id, accountStatus: "active" },
        data: { isLookingForGame: true }
      });

      if (activeAccount.count !== 1) {
        throw new Error("ACCOUNT_DEACTIVATED");
      }
      await assertActiveCourtIds(tx, [body.preferredCourtId]);

      const preferredDistricts = body.preferredDistricts ?? [];
      const customVenueTitle = normalizeOptionalText(body.customVenueTitle);
      const customVenueAddress = normalizeOptionalText(body.customVenueAddress);
      const runningRoute = normalizeOptionalText(body.runningRoute);
      const runningRoutePoints =
        isRouteSport(body.sport) && body.runningRoutePoints ? (body.runningRoutePoints as Prisma.InputJsonValue) : Prisma.JsonNull;
      const created = await tx.gameSearch.create({
        data: {
          inviteSlug: body.inviteSlug ?? null,
          createdByUserId: user.id,
          preferredCourtId: body.preferredCourtId ?? null,
          customVenueTitle: body.preferredCourtId ? null : customVenueTitle,
          customVenueAddress: body.preferredCourtId ? null : customVenueAddress,
          runningRoute: isRouteSport(body.sport) ? runningRoute : null,
          runningRoutePoints,
          preferredDistricts,
          preferredDays,
          preferredTimeRanges: body.preferredTimeRanges,
          searchType: body.searchType,
          hotWindow: body.searchType === "hot" && !explicitHotStartsAt ? body.hotWindow ?? null : null,
          hotStartsAt,
          durationMinutes: body.searchType === "hot" ? body.durationMinutes ?? null : null,
          hasCourtBooked: body.hasCourtBooked ?? false,
          sport: body.sport,
          selfLevel: hasSportProfile ? null : body.selfLevel ?? null,
          selfLevelUnknown: hasSportProfile ? false : (body.selfLevelUnknown ?? false),
          desiredLevelMin: body.desiredLevelMin ?? 1,
          desiredLevelMax: body.desiredLevelMax ?? 10,
          format: body.format,
          playersNeeded: body.playersNeeded ?? 1,
          comment: body.comment,
          status: "active",
          isActive: true
        },
        include: {
          preferredCourt: true
        }
      });
      return created;
    });

    return ok({
      gameSearch: {
        ...gameSearch,
        createdAt: gameSearch.createdAt.toISOString(),
        updatedAt: gameSearch.updatedAt.toISOString(),
        hotStartsAt: gameSearch.hotStartsAt?.toISOString() ?? null
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "ACCOUNT_DEACTIVATED") {
      return fail("Аккаунт деактивирован", 403);
    }

    if (getErrorMessage(error) === "COURT_UNAVAILABLE") {
      return fail("Клуб временно недоступен", 409);
    }

    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

function normalizeOptionalText(value: string | null | undefined) {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}
