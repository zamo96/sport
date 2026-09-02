import { AccountStatus, AdminAuditAction, Prisma, type User } from "@prisma/client";

import { resolveLocationFromCity, resolveLocationFromDistrict } from "@/lib/geo";
import { prisma } from "@/lib/prisma";
import { getPrimarySportLevel, normalizeSports, normalizeSportLevels } from "@/lib/sport-levels";
import type { AdminPlayerProfilePatch, AdminPlayerStatusPatch } from "@/lib/validators";

const adminPlayerSummarySelect = {
  id: true,
  email: true,
  name: true,
  age: true,
  gender: true,
  city: true,
  district: true,
  preferredDistricts: true,
  preferredSports: true,
  sportLevels: true,
  avatarUrl: true,
  isLookingForGame: true,
  isVerified: true,
  onboardingCompleted: true,
  accountStatus: true,
  deactivatedAt: true,
  createdAt: true,
  lastActiveAt: true,
  updatedAt: true
} satisfies Prisma.UserSelect;

const adminPlayerDetailSelect = {
  ...adminPlayerSummarySelect,
  tennisLevel: true,
  bio: true,
  profilePhotoUrls: true,
  profileVideoUrls: true,
  preferredPlayFormat: true,
  preferredSurface: true,
  availableDays: true,
  availableTimeRanges: true,
  availableTimeSlots: true,
  availabilityByDay: true,
  notificationMatches: true,
  notificationMessages: true,
  notificationGames: true,
  notificationSound: true,
  deactivationReason: true
} satisfies Prisma.UserSelect;

export type AdminPlayersQuery = {
  q: string;
  status: "all" | AccountStatus;
  page: number;
  limit: number;
};

export async function listAdminPlayers(query: AdminPlayersQuery) {
  const where: Prisma.UserWhereInput = {
    ...(query.status === "all" ? {} : { accountStatus: query.status }),
    ...(query.q
      ? {
          OR: [
            { id: { contains: query.q, mode: "insensitive" } },
            { email: { contains: query.q, mode: "insensitive" } },
            { name: { contains: query.q, mode: "insensitive" } },
            { city: { contains: query.q, mode: "insensitive" } },
            { district: { contains: query.q, mode: "insensitive" } }
          ]
        }
      : {})
  };
  const skip = (query.page - 1) * query.limit;
  const [total, items] = await prisma.$transaction([
    prisma.user.count({ where }),
    prisma.user.findMany({
      where,
      skip,
      take: query.limit,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      select: adminPlayerSummarySelect
    })
  ]);

  return {
    items: items.map(serializeAdminPlayer),
    pagination: {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.ceil(total / query.limit)
    }
  };
}

export async function getAdminPlayer(userId: string) {
  const [player, auditLogs] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: adminPlayerDetailSelect }),
    prisma.adminAuditLog.findMany({
      where: { targetUserId: userId },
      orderBy: { createdAt: "desc" },
      take: 100,
      select: {
        id: true,
        action: true,
        actorEmail: true,
        reason: true,
        before: true,
        after: true,
        createdAt: true
      }
    })
  ]);

  if (!player) {
    throw new Error("PLAYER_NOT_FOUND");
  }

  return { player: serializeAdminPlayer(player), auditLogs };
}

export async function updateAdminPlayerProfile(
  actor: Pick<User, "id" | "email">,
  targetUserId: string,
  input: AdminPlayerProfilePatch
) {
  await prisma.$transaction(async (tx) => {
    const current = await tx.user.findUnique({ where: { id: targetUserId } });

    if (!current) {
      throw new Error("PLAYER_NOT_FOUND");
    }

    assertExpectedUpdatedAt(current.updatedAt, input.expectedUpdatedAt);
    const data = await buildProfileUpdateData(current, input.profile);
    const result = await tx.user.updateMany({
      where: { id: targetUserId, updatedAt: current.updatedAt },
      data
    });

    if (result.count !== 1) {
      throw new Error("STALE_PLAYER_UPDATE");
    }

    const updated = await tx.user.findUniqueOrThrow({ where: { id: targetUserId } });
    const changedFields = Object.entries(data)
      .filter(([, value]) => value !== undefined)
      .map(([key]) => key as keyof User)
      .filter((key) => JSON.stringify(toAuditValue(current[key])) !== JSON.stringify(toAuditValue(updated[key])));
    await tx.adminAuditLog.create({
      data: {
        actorUserId: actor.id,
        actorEmail: actor.email,
        targetUserId: current.id,
        targetEmail: current.email,
        action: AdminAuditAction.PROFILE_UPDATED,
        before: toAuditFields(current, changedFields),
        after: toAuditFields(updated, changedFields)
      }
    });
  });

  return getAdminPlayer(targetUserId);
}

export async function updateAdminPlayerStatus(
  actor: Pick<User, "id" | "email">,
  targetUserId: string,
  input: AdminPlayerStatusPatch
) {
  const effects = await prisma.$transaction(async (tx) => {
    const current = await tx.user.findUnique({ where: { id: targetUserId } });

    if (!current) {
      throw new Error("PLAYER_NOT_FOUND");
    }

    if (actor.id === current.id && input.status === AccountStatus.deactivated) {
      throw new Error("SELF_DEACTIVATION_FORBIDDEN");
    }

    assertExpectedUpdatedAt(current.updatedAt, input.expectedUpdatedAt);
    if (current.accountStatus === input.status) {
      return { sessionsRevoked: 0, pushDevicesDisabled: 0, searchesClosed: 0 };
    }

    const deactivating = input.status === AccountStatus.deactivated;
    const now = new Date();
    const userUpdate = await tx.user.updateMany({
      where: { id: current.id, updatedAt: current.updatedAt, accountStatus: current.accountStatus },
      data: deactivating
        ? {
            accountStatus: AccountStatus.deactivated,
            deactivatedAt: now,
            deactivationReason: input.reason
          }
        : {
            accountStatus: AccountStatus.active,
            deactivatedAt: null,
            deactivationReason: null
          }
    });

    if (userUpdate.count !== 1) {
      throw new Error("STALE_PLAYER_UPDATE");
    }

    const [sessions, pushDevices, searches] = deactivating
      ? await Promise.all([
          tx.session.deleteMany({ where: { userId: current.id } }),
          tx.pushDevice.updateMany({ where: { userId: current.id, isActive: true }, data: { isActive: false } }),
          tx.gameSearch.updateMany({
            where: { createdByUserId: current.id, isActive: true },
            data: { isActive: false, status: "closed" }
          })
        ])
      : [{ count: 0 }, { count: 0 }, { count: 0 }];

    const updated = await tx.user.findUniqueOrThrow({ where: { id: current.id } });
    await tx.adminAuditLog.create({
      data: {
        actorUserId: actor.id,
        actorEmail: actor.email,
        targetUserId: current.id,
        targetEmail: current.email,
        action: deactivating ? AdminAuditAction.ACCOUNT_DEACTIVATED : AdminAuditAction.ACCOUNT_REACTIVATED,
        reason: input.reason,
        before: toAuditFields(current, ["accountStatus", "deactivatedAt", "deactivationReason"]),
        after: toAuditFields(updated, ["accountStatus", "deactivatedAt", "deactivationReason"])
      }
    });

    return {
      sessionsRevoked: sessions.count,
      pushDevicesDisabled: pushDevices.count,
      searchesClosed: searches.count
    };
  });

  const { player } = await getAdminPlayer(targetUserId);
  return { player, effects };
}

function assertExpectedUpdatedAt(actual: Date, expected: string) {
  if (actual.getTime() !== new Date(expected).getTime()) {
    throw new Error("STALE_PLAYER_UPDATE");
  }
}

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function jsonRecord(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function serializeAdminPlayer<T extends Record<string, unknown>>(player: T) {
  return {
    ...player,
    preferredDistricts: stringArray(player.preferredDistricts),
    preferredSports: stringArray(player.preferredSports),
    sportLevels: jsonRecord(player.sportLevels),
    ...(Object.prototype.hasOwnProperty.call(player, "profilePhotoUrls")
      ? { profilePhotoUrls: stringArray(player.profilePhotoUrls) }
      : {}),
    ...(Object.prototype.hasOwnProperty.call(player, "profileVideoUrls")
      ? { profileVideoUrls: stringArray(player.profileVideoUrls) }
      : {}),
    ...(Object.prototype.hasOwnProperty.call(player, "availableDays")
      ? { availableDays: stringArray(player.availableDays) }
      : {}),
    ...(Object.prototype.hasOwnProperty.call(player, "availableTimeRanges")
      ? { availableTimeRanges: stringArray(player.availableTimeRanges) }
      : {}),
    ...(Object.prototype.hasOwnProperty.call(player, "availableTimeSlots")
      ? { availableTimeSlots: stringArray(player.availableTimeSlots) }
      : {}),
    ...(Object.prototype.hasOwnProperty.call(player, "availabilityByDay")
      ? { availabilityByDay: jsonRecord(player.availabilityByDay) }
      : {})
  };
}

async function buildProfileUpdateData(current: User, profile: AdminPlayerProfilePatch["profile"]) {
  const data: Prisma.UserUncheckedUpdateManyInput = { ...profile };

  if (profile.profilePhotoUrls) {
    data.profilePhotoUrls = Array.from(new Set(profile.profilePhotoUrls.map((url) => url.trim()).filter(Boolean)));
  }
  if (profile.profileVideoUrls) {
    data.profileVideoUrls = Array.from(new Set(profile.profileVideoUrls.map((url) => url.trim()).filter(Boolean)));
  }

  const locationChanged = profile.city !== undefined || profile.district !== undefined || profile.preferredDistricts !== undefined;
  if (locationChanged) {
    const preferredDistricts = profile.preferredDistricts ?? stringArray(current.preferredDistricts);
    const primaryDistrict = preferredDistricts[0] ?? profile.district ?? current.district ?? null;
    const city = profile.city ?? current.city;
    const location = (primaryDistrict ? resolveLocationFromDistrict(primaryDistrict) : null) ?? (city ? await resolveLocationFromCity(city) : null);
    data.preferredDistricts = preferredDistricts;
    data.district = primaryDistrict;
    data.homeLat = location?.lat ?? current.homeLat;
    data.homeLng = location?.lng ?? current.homeLng;
  }

  const sportProfileChanged =
    profile.preferredSports !== undefined || profile.sportLevels !== undefined || profile.tennisLevel !== undefined;
  if (sportProfileChanged) {
    const preferredSports = normalizeSports(profile.preferredSports ?? current.preferredSports);
    const fallbackLevel = profile.tennisLevel ?? current.tennisLevel ?? 5;
    const sportLevels = normalizeSportLevels(profile.sportLevels ?? current.sportLevels, preferredSports, fallbackLevel);
    data.preferredSports = preferredSports;
    data.sportLevels = sportLevels;
    data.tennisLevel = getPrimarySportLevel(preferredSports, sportLevels, fallbackLevel);
  }

  const availabilityChanged =
    profile.availableDays !== undefined || profile.availableTimeRanges !== undefined || profile.availabilityByDay !== undefined;
  if (availabilityChanged) {
    const availabilityByDay = profile.availabilityByDay ??
      (current.availabilityByDay && typeof current.availabilityByDay === "object" && !Array.isArray(current.availabilityByDay)
        ? (current.availabilityByDay as Record<string, string[]>)
        : {});
    const nonEmptyAvailability = Object.fromEntries(
      Object.entries(availabilityByDay).filter(([, ranges]) => Array.isArray(ranges) && ranges.length > 0)
    );
    const entries = Object.entries(nonEmptyAvailability);
    const availableDays = profile.availableDays ?? (entries.length ? entries.map(([day]) => day) : stringArray(current.availableDays));
    const availableTimeRanges =
      profile.availableTimeRanges ??
      (entries.length ? Array.from(new Set(entries.flatMap(([, ranges]) => ranges))) : stringArray(current.availableTimeRanges));
    data.availabilityByDay = nonEmptyAvailability;
    data.availableDays = availableDays;
    data.availableTimeRanges = availableTimeRanges;
    data.availableTimeSlots = availableDays.flatMap((day) =>
      (nonEmptyAvailability[day] ?? availableTimeRanges).map((timeRange) => `${day}-${timeRange}`)
    );
  }

  return data;
}

function toAuditFields(user: User, keys: Array<keyof User>): Prisma.InputJsonObject {
  return Object.fromEntries(
    keys.map((key) => {
      return [key, toAuditValue(user[key])];
    })
  ) as Prisma.InputJsonObject;
}

function toAuditValue(value: User[keyof User]) {
  return value instanceof Date ? value.toISOString() : value;
}
