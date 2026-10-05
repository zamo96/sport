import { AdminCourtAuditAction, CourtStatus, Prisma, type User } from "@prisma/client";

import { prisma } from "@/lib/prisma";
import { normalizeClubAddressIdentity, normalizeClubIdentityText } from "@/lib/club-sync";
import type { AdminClubProfilePatch, AdminClubsQuery, AdminClubStatusPatch } from "@/lib/validators";
import { accountContact } from "@/lib/account-contact";

const LIST_FIELDS = {
  id: true,
  name: true,
  address: true,
  city: true,
  district: true,
  locationLat: true,
  locationLng: true,
  status: true,
  surface: true,
  setting: true,
  supportedSports: true,
  photoUrl: true,
  priceRange: true,
  rating: true,
  sourceType: true,
  sourceExternalId: true,
  lastCheckedAt: true,
  updatedAt: true,
  manualOverrideFields: true,
  _count: { select: { syncChanges: { where: { status: "pending" } } } }
} satisfies Prisma.CourtSelect;

const DETAIL_INCLUDE = {
  nearestMetro: true,
  metroLinks: { include: { metro: true }, orderBy: { position: "asc" as const } },
  _count: {
    select: {
      members: true,
      gameRequests: true,
      gameSearches: true,
      regularPairs: true,
      personalActivities: true,
      syncChanges: { where: { status: "pending" } }
    }
  }
} satisfies Prisma.CourtInclude;

const EDITABLE_FIELDS = [
  "name",
  "address",
  "city",
  "district",
  "locationLat",
  "locationLng",
  "surface",
  "setting",
  "supportedSports",
  "phone",
  "workingHours",
  "yandexMapsUrl",
  "websiteUrl",
  "bookingUrl",
  "about",
  "amenities",
  "messengerType",
  "messengerUrl",
  "photoUrl",
  "photoUrls",
  "priceRange",
  "metroIds"
] as const;

export async function listAdminClubs(query: AdminClubsQuery) {
  const where: Prisma.CourtWhereInput = {
    ...(query.status === "all" ? {} : { status: query.status }),
    ...(query.city === "all" ? {} : { city: query.city }),
    ...(query.sourceType === "all" ? {} : { sourceType: query.sourceType }),
    ...(query.sport === "all" ? {} : { supportedSports: { array_contains: [query.sport] } }),
    ...(query.q
      ? {
          OR: [
            { id: { contains: query.q, mode: "insensitive" } },
            { name: { contains: query.q, mode: "insensitive" } },
            { address: { contains: query.q, mode: "insensitive" } },
            { city: { contains: query.q, mode: "insensitive" } },
            { district: { contains: query.q, mode: "insensitive" } },
            { sourceExternalId: { contains: query.q, mode: "insensitive" } }
          ]
        }
      : {})
  };
  const skip = (query.page - 1) * query.limit;
  const [total, items, cities, sourceTypes] = await prisma.$transaction([
    prisma.court.count({ where }),
    prisma.court.findMany({
      where,
      skip,
      take: query.limit,
      orderBy: [{ updatedAt: "desc" }, { id: "desc" }],
      select: LIST_FIELDS
    }),
    prisma.court.findMany({ distinct: ["city"], orderBy: { city: "asc" }, select: { city: true } }),
    prisma.court.findMany({ distinct: ["sourceType"], orderBy: { sourceType: "asc" }, select: { sourceType: true } })
  ]);

  return {
    items: items.map(({ _count, ...club }) => ({
      ...serializeJsonArrays(club),
      pendingProposalCount: _count.syncChanges
    })),
    pagination: { page: query.page, limit: query.limit, total, totalPages: Math.ceil(total / query.limit) },
    filters: {
      cities: cities.map((item) => item.city),
      sourceTypes: sourceTypes.map((item) => item.sourceType)
    }
  };
}

export async function getAdminClub(courtId: string) {
  const [club, auditLogs] = await Promise.all([
    prisma.court.findUnique({ where: { id: courtId }, include: DETAIL_INCLUDE }),
    prisma.adminCourtAuditLog.findMany({
      where: { courtId },
      orderBy: { createdAt: "desc" },
      take: 100,
      select: { id: true, action: true, actorEmail: true, reason: true, before: true, after: true, createdAt: true }
    })
  ]);
  if (!club) throw new Error("CLUB_NOT_FOUND");

  const { _count, metroLinks, nearestMetro: _nearestMetro, ...fields } = club;
  return {
    club: {
      ...serializeJsonArrays(fields),
      metroIds: metroLinks.map((link) => link.metroId),
      metroNames: metroLinks.map((link) => link.metro.name),
      pendingProposalCount: _count.syncChanges,
      usageCounts: {
        members: _count.members,
        gameRequests: _count.gameRequests,
        gameSearches: _count.gameSearches,
        regularPairs: _count.regularPairs,
        personalActivities: _count.personalActivities
      }
    },
    auditLogs
  };
}

export async function updateAdminClubProfile(
  actor: Pick<User, "id" | "email">,
  courtId: string,
  input: AdminClubProfilePatch
) {
  await prisma.$transaction(async (tx) => {
    const current = await tx.court.findUnique({
      where: { id: courtId },
      include: { metroLinks: { orderBy: { position: "asc" } } }
    });
    if (!current) throw new Error("CLUB_NOT_FOUND");
    assertExpectedUpdatedAt(current.updatedAt, input.expectedUpdatedAt);

    if (input.profile.city !== undefined && (input.profile.district === undefined || input.profile.metroIds === undefined)) {
      throw new Error("CLUB_CITY_RELATIONS_REQUIRED");
    }
    const nextCity = input.profile.city ?? current.city;
    const nextDistrict = input.profile.district !== undefined ? input.profile.district : current.district;
    const currentMetroIds = current.metroLinks.map((link) => link.metroId);
    const nextMetroIds = input.profile.metroIds ?? currentMetroIds;
    await validateClubRelations(tx, nextCity, nextDistrict, nextMetroIds);

    const changedInputFields = EDITABLE_FIELDS.filter((field) => {
      if (!Object.prototype.hasOwnProperty.call(input.profile, field)) return false;
      const before = field === "metroIds" ? currentMetroIds : current[field as keyof typeof current];
      return JSON.stringify(before ?? null) !== JSON.stringify(input.profile[field as keyof typeof input.profile] ?? null);
    });
    if (!changedInputFields.length) return;
    const manualOverrideFields = Array.from(new Set([...stringArray(current.manualOverrideFields), ...changedInputFields]));
    const metroIds = input.profile.metroIds;
    const profile = Object.fromEntries(
      Object.entries(input.profile).filter(([field]) => field !== "metroIds" && changedInputFields.includes(field as (typeof EDITABLE_FIELDS)[number]))
    ) as Omit<typeof input.profile, "metroIds">;
    const data = {
      ...profile,
      ...(profile.name !== undefined ? { normalizedName: normalizeClubIdentityText(profile.name) } : {}),
      ...(profile.address !== undefined ? { normalizedAddress: normalizeClubAddressIdentity(profile.address) } : {}),
      ...(profile.supportedSports ? { supportedSports: profile.supportedSports as Prisma.InputJsonValue } : {}),
      ...(profile.amenities ? { amenities: profile.amenities as Prisma.InputJsonValue } : {}),
      ...(profile.photoUrls ? { photoUrls: profile.photoUrls as Prisma.InputJsonValue } : {}),
      manualOverrideFields: manualOverrideFields as Prisma.InputJsonValue,
      moderatedAt: new Date(),
      moderatedByEmail: actor.email
    } satisfies Prisma.CourtUncheckedUpdateInput;

    const result = await tx.court.updateMany({ where: { id: courtId, updatedAt: current.updatedAt }, data });
    if (result.count !== 1) throw new Error("STALE_CLUB_UPDATE");

    if (metroIds !== undefined && changedInputFields.includes("metroIds")) {
      await tx.courtMetro.deleteMany({ where: { courtId } });
      if (metroIds.length) {
        await tx.courtMetro.createMany({
          data: metroIds.map((metroId, position) => ({ courtId, metroId, position }))
        });
      }
      await tx.court.update({ where: { id: courtId }, data: { nearestMetroId: metroIds[0] ?? null } });
    }

    const updated = await tx.court.findUniqueOrThrow({
      where: { id: courtId },
      include: { metroLinks: { orderBy: { position: "asc" } } }
    });
    await tx.adminCourtAuditLog.create({
      data: {
        actorUserId: actor.id,
        actorEmail: accountContact(actor),
        courtId,
        courtName: updated.name,
        action: AdminCourtAuditAction.PROFILE_UPDATED,
        reason: input.moderationNote,
        before: auditSnapshot(current, changedInputFields),
        after: auditSnapshot(updated, changedInputFields)
      }
    });
  });
  return getAdminClub(courtId);
}

export async function updateAdminClubStatus(
  actor: Pick<User, "id" | "email">,
  courtId: string,
  input: AdminClubStatusPatch
) {
  await prisma.$transaction(async (tx) => {
    const current = await tx.court.findUnique({ where: { id: courtId } });
    if (!current) throw new Error("CLUB_NOT_FOUND");
    assertExpectedUpdatedAt(current.updatedAt, input.expectedUpdatedAt);
    if (current.status === input.status) return;
    if (current.status === CourtStatus.archived && input.status !== CourtStatus.needs_review) {
      throw new Error("CLUB_ARCHIVED_TRANSITION_INVALID");
    }
    if (input.status === CourtStatus.active && stringArray(current.supportedSports).length === 0) {
      throw new Error("CLUB_SPORTS_REQUIRED");
    }
    if (
      input.status === CourtStatus.active &&
      (!current.name.trim() ||
        !current.address.trim() ||
        !current.priceRange.trim() ||
        !Number.isFinite(current.locationLat) ||
        Math.abs(current.locationLat) > 90 ||
        !Number.isFinite(current.locationLng) ||
        Math.abs(current.locationLng) > 180)
    ) {
      throw new Error("CLUB_PROFILE_INCOMPLETE");
    }

    const result = await tx.court.updateMany({
      where: { id: courtId, updatedAt: current.updatedAt },
      data: {
        status: input.status,
        manualStatusOverride: true,
        moderatedAt: new Date(),
        moderatedByEmail: actor.email
      }
    });
    if (result.count !== 1) throw new Error("STALE_CLUB_UPDATE");
    const updated = await tx.court.findUniqueOrThrow({ where: { id: courtId } });
    await tx.adminCourtAuditLog.create({
      data: {
        actorUserId: actor.id,
        actorEmail: accountContact(actor),
        courtId,
        courtName: updated.name,
        action: AdminCourtAuditAction.STATUS_CHANGED,
        reason: input.reason,
        before: { status: current.status, manualStatusOverride: current.manualStatusOverride },
        after: { status: updated.status, manualStatusOverride: updated.manualStatusOverride }
      }
    });
  });
  return getAdminClub(courtId);
}

async function validateClubRelations(
  tx: Prisma.TransactionClient,
  city: string,
  district: string | null | undefined,
  metroIds: string[] | undefined
) {
  const cityExists = await tx.district.count({ where: { city } });
  if (!cityExists) throw new Error("CLUB_CITY_INVALID");
  if (district != null) {
    const districtExists = await tx.district.count({ where: { code: district, city } });
    if (!districtExists) throw new Error("CLUB_DISTRICT_INVALID");
  }
  if (metroIds) {
    const metros = await tx.metro.findMany({ where: { id: { in: metroIds } }, select: { id: true, city: true } });
    if (metros.length !== metroIds.length || metros.some((metro) => metro.city !== city)) {
      throw new Error("CLUB_METRO_INVALID");
    }
  }
}

function assertExpectedUpdatedAt(actual: Date, expected: string) {
  if (actual.getTime() !== new Date(expected).getTime()) throw new Error("STALE_CLUB_UPDATE");
}

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function serializeJsonArrays<T extends Record<string, unknown>>(club: T) {
  return {
    ...club,
    supportedSports: stringArray(club.supportedSports),
    amenities: stringArray(club.amenities),
    photoUrls: stringArray(club.photoUrls),
    manualOverrideFields: stringArray(club.manualOverrideFields)
  };
}

function auditSnapshot(
  court: Record<string, unknown> & { metroLinks?: Array<{ metroId: string }> },
  fields: readonly (typeof EDITABLE_FIELDS)[number][]
) {
  return Object.fromEntries(
    fields.map((field) => [field, field === "metroIds" ? court.metroLinks?.map((link) => link.metroId) ?? [] : court[field] ?? null])
  ) as Prisma.InputJsonObject;
}
