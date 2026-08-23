import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => {
  const tx = {
    court: { findUnique: vi.fn(), findUniqueOrThrow: vi.fn(), updateMany: vi.fn(), update: vi.fn() },
    courtMetro: { deleteMany: vi.fn(), createMany: vi.fn() },
    district: { count: vi.fn() },
    metro: { findMany: vi.fn() },
    adminCourtAuditLog: { create: vi.fn() }
  };
  const prisma = {
    $transaction: vi.fn(),
    court: { findUnique: vi.fn() },
    adminCourtAuditLog: { findMany: vi.fn() }
  };
  return { tx, prisma };
});

vi.mock("@/lib/prisma", () => ({ prisma: mocks.prisma }));

import { updateAdminClubProfile, updateAdminClubStatus } from "@/server/admin-clubs";

const updatedAt = new Date("2026-08-23T10:00:00.000Z");
const currentClub = {
  id: "club-1",
  name: "Старый клуб",
  address: "Старый адрес",
  city: "Москва",
  district: "central",
  locationLat: 55.75,
  locationLng: 37.61,
  priceRange: "1000–2000 ₽",
  supportedSports: ["tennis"],
  status: "active",
  manualOverrideFields: [],
  manualStatusOverride: false,
  updatedAt,
  metroLinks: [{ metroId: "metro-1" }]
};

function detail(club = currentClub) {
  return {
    ...club,
    nearestMetro: null,
    metroLinks: club.metroLinks.map((link) => ({ ...link, metro: { name: "Тверская" } })),
    _count: { members: 0, gameRequests: 0, gameSearches: 0, regularPairs: 0, personalActivities: 0, syncChanges: 0 }
  };
}

describe("admin club moderation", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.prisma.$transaction.mockImplementation(async (callback: (tx: typeof mocks.tx) => unknown) => callback(mocks.tx));
    mocks.tx.court.findUnique.mockResolvedValue(currentClub);
    mocks.tx.court.findUniqueOrThrow.mockResolvedValue({ ...currentClub, name: "Новый клуб", manualOverrideFields: ["name"] });
    mocks.tx.court.updateMany.mockResolvedValue({ count: 1 });
    mocks.tx.court.update.mockResolvedValue(currentClub);
    mocks.tx.district.count.mockResolvedValue(1);
    mocks.tx.metro.findMany.mockResolvedValue([{ id: "metro-1", city: "Москва" }]);
    mocks.prisma.court.findUnique.mockResolvedValue(detail({ ...currentClub, name: "Новый клуб" }));
    mocks.prisma.adminCourtAuditLog.findMany.mockResolvedValue([]);
  });

  it("uses an optimistic lock and audits only actual changed fields", async () => {
    await updateAdminClubProfile(
      { id: "admin-1", email: "admin@example.com" },
      currentClub.id,
      {
        expectedUpdatedAt: updatedAt.toISOString(),
        profile: { name: "Новый клуб", address: currentClub.address },
        moderationNote: "Исправлено название"
      }
    );

    expect(mocks.tx.court.updateMany).toHaveBeenCalledWith({
      where: { id: currentClub.id, updatedAt },
      data: expect.objectContaining({
        name: "Новый клуб",
        normalizedName: "новый",
        manualOverrideFields: ["name"],
        moderatedByEmail: "admin@example.com"
      })
    });
    expect(mocks.tx.adminCourtAuditLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        action: "PROFILE_UPDATED",
        reason: "Исправлено название",
        before: { name: "Старый клуб" },
        after: { name: "Новый клуб" }
      })
    });
  });

  it("rejects stale updates before writes and audit", async () => {
    await expect(
      updateAdminClubProfile(
        { id: "admin-1", email: "admin@example.com" },
        currentClub.id,
        { expectedUpdatedAt: "2026-08-23T09:00:00.000Z", profile: { name: "Новый клуб" } }
      )
    ).rejects.toThrow("STALE_CLUB_UPDATE");
    expect(mocks.tx.court.updateMany).not.toHaveBeenCalled();
    expect(mocks.tx.adminCourtAuditLog.create).not.toHaveBeenCalled();
  });

  it("does not write or audit a status no-op", async () => {
    await updateAdminClubStatus(
      { id: "admin-1", email: "admin@example.com" },
      currentClub.id,
      { expectedUpdatedAt: updatedAt.toISOString(), status: "active", reason: "Оставить опубликованным" }
    );
    expect(mocks.tx.court.updateMany).not.toHaveBeenCalled();
    expect(mocks.tx.adminCourtAuditLog.create).not.toHaveBeenCalled();
  });

  it("requires an archived club to return through review", async () => {
    mocks.tx.court.findUnique.mockResolvedValue({ ...currentClub, status: "archived" });
    await expect(
      updateAdminClubStatus(
        { id: "admin-1", email: "admin@example.com" },
        currentClub.id,
        { expectedUpdatedAt: updatedAt.toISOString(), status: "active", reason: "Вернуть клуб" }
      )
    ).rejects.toThrow("CLUB_ARCHIVED_TRANSITION_INVALID");
  });
});
