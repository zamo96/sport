import { NextRequest } from "next/server";

import { destroySession, getSessionUser, requireSessionUser } from "@/lib/auth";
import { resolveLocationFromDistrict } from "@/lib/geo";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { resolveRequestLocale } from "@/lib/locales";
import { prisma } from "@/lib/prisma";
import { getPrimarySportLevel, normalizeSports, normalizeSportLevels } from "@/lib/sport-levels";
import { updateMeSchema } from "@/lib/validators";
import {
  ensureLegacyLocation,
  getLocationPlace,
  shouldPreserveCurrentGlobalLocation
} from "@/server/locations";
import { serializeMe } from "@/server/serializers";

export async function GET(request: NextRequest) {
  const user = await getSessionUser();

  if (!user) {
    return fail("Требуется авторизация", 401);
  }

  const hydratedUser = await prisma.user.findUnique({
    where: { id: user.id },
    include: { location: { include: { serviceArea: true } } }
  });

  const requestLocale = resolveRequestLocale({ acceptLanguage: request.headers.get("accept-language") });
  return ok({
    user: hydratedUser
      ? serializeMe(hydratedUser, requestLocale)
      : serializeMe({ ...user, location: null }, requestLocale)
  });
}

export async function PATCH(request: NextRequest) {
  try {
    const currentUser = await requireSessionUser();
    const body = updateMeSchema.parse(await request.json());
    const preservesCurrentGlobalLocation = shouldPreserveCurrentGlobalLocation(
      body.locationPlaceId,
      currentUser.locationPlaceId
    );
    const selectedPlace = body.locationPlaceId
      ? await getLocationPlace(body.locationPlaceId)
      : preservesCurrentGlobalLocation && currentUser.locationPlaceId
        ? await getLocationPlace(currentUser.locationPlaceId)
        : body.city
          ? await ensureLegacyLocation(body.city)
          : null;
    if (!selectedPlace) {
      return fail("Выбранный город не найден. Выполните поиск города ещё раз", 404);
    }

    const submittedDistricts = body.preferredDistricts ?? [];
    const preferredDistricts = selectedPlace.coverage.districtsEnabled
      ? submittedDistricts.filter((district) => isDistrictCompatible(selectedPlace.coverage.legacyCity, district))
      : [];
    const requestedPrimaryDistrict = preferredDistricts[0] ?? body.district ?? null;
    const primaryDistrict =
      selectedPlace.coverage.districtsEnabled && isDistrictCompatible(selectedPlace.coverage.legacyCity, requestedPrimaryDistrict)
        ? requestedPrimaryDistrict
        : null;
    const districtLocation = primaryDistrict ? resolveLocationFromDistrict(primaryDistrict) : null;
    const preferredSports = normalizeSports(body.preferredSports);
    const fallbackSportLevel = body.tennisLevel ?? currentUser.tennisLevel ?? 5;
    const sportLevels = normalizeSportLevels(body.sportLevels, preferredSports, fallbackSportLevel);
    const primarySportLevel = getPrimarySportLevel(preferredSports, sportLevels, fallbackSportLevel);
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
        city: selectedPlace.city,
        locationPlaceId: selectedPlace.id,
        locationSource: body.locationPlaceId
          ? body.locationSource ??
            (body.locationPlaceId === currentUser.locationPlaceId ? currentUser.locationSource : "manual")
          : preservesCurrentGlobalLocation
            ? currentUser.locationSource
            : "legacy",
        district: primaryDistrict,
        preferredDistricts,
        homeLat: districtLocation?.lat ?? selectedPlace.latitude,
        homeLng: districtLocation?.lng ?? selectedPlace.longitude,
        tennisLevel: primarySportLevel,
        preferredSports,
        sportLevels,
        preferredPlayFormat: body.preferredPlayFormat,
        preferredSurface: body.preferredSurface,
        bio: body.bio,
        avatarUrl: body.avatarUrl ?? currentUser.avatarUrl,
        profilePhotoUrls:
          body.profilePhotoUrls === undefined
            ? undefined
            : Array.from(new Set(body.profilePhotoUrls.map((url) => url.trim()).filter(Boolean))).slice(0, 6),
        profileVideoUrls:
          body.profileVideoUrls === undefined
            ? undefined
            : Array.from(new Set(body.profileVideoUrls.map((url) => url.trim()).filter(Boolean))).slice(0, 4),
        searchRadiusKm: body.searchRadiusKm ?? currentUser.searchRadiusKm,
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
      },
      include: { location: { include: { serviceArea: true } } }
    });

    const requestLocale = resolveRequestLocale({ acceptLanguage: request.headers.get("accept-language") });
    return ok({ user: serializeMe(user, requestLocale) });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

function isDistrictCompatible(legacyCity: string | null, district: string | null | undefined) {
  if (!district || !legacyCity) return false;
  if (legacyCity === "Москва") return district.startsWith("moscow_");
  if (legacyCity === "Санкт-Петербург") return !district.startsWith("moscow_") && !district.startsWith("kazan_");
  return false;
}

export async function DELETE() {
  try {
    const currentUser = await requireSessionUser();

    await prisma.user.delete({
      where: { id: currentUser.id }
    });

    await destroySession();

    return ok({ success: true });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
