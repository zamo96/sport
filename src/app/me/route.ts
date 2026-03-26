import { NextRequest } from "next/server";

import { getSessionUser, requireSessionUser } from "@/lib/auth";
import { resolveLocationFromCity, resolveLocationFromDistrict } from "@/lib/geo";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { getPrimarySportLevel, normalizeSports, normalizeSportLevels } from "@/lib/sport-levels";
import { updateMeSchema } from "@/lib/validators";

export async function GET() {
  const user = await getSessionUser();

  if (!user) {
    return fail("Требуется авторизация", 401);
  }

  return ok({ user });
}

export async function PATCH(request: NextRequest) {
  try {
    const currentUser = await requireSessionUser();
    const body = updateMeSchema.parse(await request.json());
    const location = (body.district ? resolveLocationFromDistrict(body.district) : null) ?? (await resolveLocationFromCity(body.city));
    const preferredSports = normalizeSports(body.preferredSports);
    const sportLevels = normalizeSportLevels(body.sportLevels, preferredSports, body.tennisLevel);
    const primarySportLevel = getPrimarySportLevel(preferredSports, sportLevels, body.tennisLevel);
    const availabilityByDay = Object.fromEntries(
      Object.entries(body.availabilityByDay ?? {}).filter(([, ranges]) => Array.isArray(ranges) && ranges.length > 0)
    ) as Record<string, string[]>;
    const availabilityEntries = Object.entries(availabilityByDay);
    const availableDays = availabilityEntries.length > 0 ? availabilityEntries.map(([day]) => day) : body.availableDays;
    const availableTimeRanges =
      availabilityEntries.length > 0
        ? Array.from(new Set(availabilityEntries.flatMap(([, ranges]) => ranges)))
        : body.availableTimeRanges;

    const user = await prisma.user.update({
      where: { id: currentUser.id },
      data: {
        name: body.name,
        age: body.age,
        gender: body.gender ?? null,
        city: body.city,
        district: body.district ?? null,
        homeLat: location?.lat ?? currentUser.homeLat,
        homeLng: location?.lng ?? currentUser.homeLng,
        tennisLevel: primarySportLevel,
        preferredSports,
        sportLevels,
        preferredPlayFormat: body.preferredPlayFormat,
        preferredSurface: body.preferredSurface,
        bio: body.bio,
        avatarUrl: body.avatarUrl ?? currentUser.avatarUrl,
        searchRadiusKm: body.searchRadiusKm,
        availableDays,
        availableTimeRanges,
        availabilityByDay,
        availableTimeSlots: availableDays.flatMap((day) =>
          (availabilityByDay[day] ?? availableTimeRanges).map((timeRange) => `${day}-${timeRange}`)
        ),
        isLookingForGame: body.isLookingForGame ?? currentUser.isLookingForGame,
        notificationGames: body.notificationGames ?? currentUser.notificationGames,
        notificationMatches: body.notificationMatches ?? currentUser.notificationMatches,
        notificationMessages: body.notificationMessages ?? currentUser.notificationMessages,
        notificationSound: body.notificationSound ?? currentUser.notificationSound,
        onboardingCompleted: true
      }
    });

    return ok({ user });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
