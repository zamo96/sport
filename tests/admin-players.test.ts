import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => {
  const tx = {
    user: {
      findUnique: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      updateMany: vi.fn()
    },
    session: { deleteMany: vi.fn() },
    pushDevice: { updateMany: vi.fn() },
    gameSearch: { updateMany: vi.fn() },
    adminAuditLog: { create: vi.fn() }
  };
  const prisma = {
    $transaction: vi.fn(),
    user: { findUnique: vi.fn() },
    adminAuditLog: { findMany: vi.fn() }
  };
  return { tx, prisma };
});

vi.mock("@/lib/prisma", () => ({ prisma: mocks.prisma }));

import { updateAdminPlayerProfile, updateAdminPlayerStatus } from "@/server/admin-players";

const updatedAt = new Date("2026-08-23T10:00:00.000Z");
const currentPlayer = {
  id: "player-1",
  email: "player@example.com",
  accountStatus: "active",
  updatedAt,
  isLookingForGame: true
};
const deactivatedPlayer = {
  ...currentPlayer,
  accountStatus: "deactivated",
  updatedAt: new Date("2026-08-23T10:01:00.000Z"),
  isLookingForGame: false,
  deactivatedAt: new Date("2026-08-23T10:01:00.000Z"),
  deactivationReason: "Нарушение правил"
};

describe("admin player moderation", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.prisma.$transaction.mockImplementation(async (callback: (tx: typeof mocks.tx) => unknown) => callback(mocks.tx));
    mocks.tx.user.findUnique.mockResolvedValue(currentPlayer);
    mocks.tx.user.findUniqueOrThrow.mockResolvedValue(deactivatedPlayer);
    mocks.tx.user.updateMany.mockResolvedValue({ count: 1 });
    mocks.tx.session.deleteMany.mockResolvedValue({ count: 3 });
    mocks.tx.pushDevice.updateMany.mockResolvedValue({ count: 2 });
    mocks.tx.gameSearch.updateMany.mockResolvedValue({ count: 1 });
    mocks.tx.adminAuditLog.create.mockResolvedValue({ id: "audit-1" });
    mocks.prisma.user.findUnique.mockResolvedValue(deactivatedPlayer);
    mocks.prisma.adminAuditLog.findMany.mockResolvedValue([]);
  });

  it("deactivates atomically and reports every revoked capability", async () => {
    const result = await updateAdminPlayerStatus(
      { id: "admin-1", email: "admin@example.com" },
      currentPlayer.id,
      {
        status: "deactivated",
        reason: "Нарушение правил",
        expectedUpdatedAt: updatedAt.toISOString()
      }
    );

    expect(mocks.tx.session.deleteMany).toHaveBeenCalledWith({ where: { userId: currentPlayer.id } });
    expect(mocks.tx.pushDevice.updateMany).toHaveBeenCalledWith({
      where: { userId: currentPlayer.id, isActive: true },
      data: { isActive: false }
    });
    expect(mocks.tx.gameSearch.updateMany).toHaveBeenCalledWith({
      where: { createdByUserId: currentPlayer.id, isActive: true },
      data: { isActive: false, status: "closed" }
    });
    expect(mocks.tx.adminAuditLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        actorEmail: "admin@example.com",
        targetEmail: currentPlayer.email,
        action: "ACCOUNT_DEACTIVATED",
        reason: "Нарушение правил"
      })
    });
    expect(result.effects).toEqual({ sessionsRevoked: 3, pushDevicesDisabled: 2, searchesClosed: 1 });
  });

  it("forbids an administrator from deactivating their own account", async () => {
    await expect(
      updateAdminPlayerStatus(
        { id: currentPlayer.id, email: currentPlayer.email },
        currentPlayer.id,
        {
          status: "deactivated",
          reason: "mistake",
          expectedUpdatedAt: updatedAt.toISOString()
        }
      )
    ).rejects.toThrow("SELF_DEACTIVATION_FORBIDDEN");

    expect(mocks.tx.user.updateMany).not.toHaveBeenCalled();
    expect(mocks.tx.session.deleteMany).not.toHaveBeenCalled();
  });

  it("rejects stale profile edits before writing or auditing", async () => {
    await expect(
      updateAdminPlayerProfile(
        { id: "admin-1", email: "admin@example.com" },
        currentPlayer.id,
        {
          expectedUpdatedAt: "2026-08-23T09:00:00.000Z",
          profile: { name: "Новое имя" }
        }
      )
    ).rejects.toThrow("STALE_PLAYER_UPDATE");

    expect(mocks.tx.user.updateMany).not.toHaveBeenCalled();
    expect(mocks.tx.adminAuditLog.create).not.toHaveBeenCalled();
  });

  it("audits only profile values that actually changed", async () => {
    mocks.tx.user.findUnique.mockResolvedValue({ ...currentPlayer, name: "Старое имя", bio: "Без изменений" });
    mocks.tx.user.findUniqueOrThrow.mockResolvedValue({ ...currentPlayer, name: "Новое имя", bio: "Без изменений" });
    mocks.prisma.user.findUnique.mockResolvedValue({ ...currentPlayer, name: "Новое имя", bio: "Без изменений" });

    await updateAdminPlayerProfile(
      { id: "admin-1", email: "admin@example.com" },
      currentPlayer.id,
      {
        expectedUpdatedAt: updatedAt.toISOString(),
        profile: { name: "Новое имя", bio: "Без изменений" }
      }
    );

    expect(mocks.tx.adminAuditLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        before: { name: "Старое имя" },
        after: { name: "Новое имя" }
      })
    });
  });
});
