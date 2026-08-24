import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => {
  const tx = {
    $queryRaw: vi.fn(),
    user: { findUnique: vi.fn(), findUniqueOrThrow: vi.fn(), update: vi.fn() },
    block: { upsert: vi.fn(), findFirst: vi.fn() },
    contentReport: { create: vi.fn(), findUnique: vi.fn(), updateMany: vi.fn() },
    match: { updateMany: vi.fn() },
    session: { deleteMany: vi.fn() },
    pushDevice: { updateMany: vi.fn() },
    gameSearch: { updateMany: vi.fn() },
    gameSearchResponse: { updateMany: vi.fn() },
    regularPair: { updateMany: vi.fn() },
    gameSearchSlotProposal: { updateMany: vi.fn() },
    gameRequest: { updateMany: vi.fn() },
    gameReport: { updateMany: vi.fn() },
    gameReportPhoto: { deleteMany: vi.fn() },
    personalActivity: { updateMany: vi.fn() },
    personalActivityPhoto: { deleteMany: vi.fn() },
    chatMessage: { findFirst: vi.fn(), updateMany: vi.fn() },
    gameSearchMessage: { findFirst: vi.fn(), updateMany: vi.fn() },
    chatMessageMedia: { deleteMany: vi.fn() },
    gameSearchMessageMedia: { deleteMany: vi.fn() }
  };
  const prisma = {
    $transaction: vi.fn(),
    contentReport: { findUnique: vi.fn(), count: vi.fn(), findMany: vi.fn() }
  };
  return { tx, prisma, sendAlert: vi.fn() };
});

vi.mock("@/lib/prisma", () => ({ prisma: mocks.prisma }));
vi.mock("@/lib/email", () => ({ sendContentReportAlert: mocks.sendAlert }));

import {
  blockUserAndReport,
  createUserContentReport,
  resolveAdminContentReport
} from "@/server/content-reports";

const now = new Date("2026-08-24T12:00:00.000Z");
const reporter = { id: "reporter-1", email: "reporter@example.com", name: "Reporter" };
const target = { id: "target-1", email: "target@example.com", name: "Target" };
const profile = {
  ...target,
  bio: "Public bio",
  avatarUrl: "https://example.com/avatar.jpg",
  profilePhotoUrls: [],
  profileVideoUrls: []
};

function reportRecord(overrides: Record<string, unknown> = {}) {
  return {
    id: "report-1",
    reporterUserId: reporter.id,
    reportedUserId: target.id,
    reporterEmail: reporter.email,
    reporterName: reporter.name,
    reportedEmail: target.email,
    reportedName: target.name,
    blockId: null,
    origin: "report",
    reason: "harassment",
    details: null,
    contentType: "profile",
    contextId: target.id,
    contextSnapshot: profile,
    status: "pending",
    dueAt: new Date(now.getTime() + 86_400_000),
    reviewedByUserId: null,
    reviewedByEmail: null,
    reviewedAt: null,
    resolutionNote: null,
    createdAt: now,
    updatedAt: now,
    ...overrides
  };
}

describe("content report service", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(now);
    vi.resetAllMocks();
    mocks.prisma.$transaction.mockImplementation(async (callback: (tx: typeof mocks.tx) => unknown) => callback(mocks.tx));
    mocks.tx.user.findUnique.mockImplementation(async ({ where }: { where: { id: string } }) => where.id === reporter.id ? reporter : target);
    mocks.tx.user.findUniqueOrThrow.mockResolvedValue(profile);
    mocks.tx.chatMessage.findFirst.mockResolvedValue(null);
    mocks.tx.gameSearchMessage.findFirst.mockResolvedValue(null);
    mocks.tx.contentReport.create.mockImplementation(async ({ data }: { data: Record<string, unknown> }) => reportRecord(data));
    mocks.tx.$queryRaw.mockResolvedValue([{ id: reporter.id }, { id: target.id }]);
    mocks.tx.block.upsert.mockResolvedValue({ id: "block-1" });
    mocks.tx.match.updateMany.mockResolvedValue({ count: 1 });
    mocks.tx.contentReport.updateMany.mockResolvedValue({ count: 1 });
    mocks.prisma.contentReport.findUnique.mockResolvedValue(reportRecord({ status: "dismissed" }));
    for (const model of [
      mocks.tx.session,
      mocks.tx.pushDevice,
      mocks.tx.gameSearch,
      mocks.tx.gameSearchResponse,
      mocks.tx.regularPair,
      mocks.tx.gameSearchSlotProposal,
      mocks.tx.gameRequest,
      mocks.tx.gameReport,
      mocks.tx.gameReportPhoto,
      mocks.tx.personalActivity,
      mocks.tx.personalActivityPhoto,
      mocks.tx.chatMessage,
      mocks.tx.gameSearchMessage,
      mocks.tx.chatMessageMedia,
      mocks.tx.gameSearchMessageMedia
    ]) {
      const method = "updateMany" in model ? model.updateMany : model.deleteMany;
      method.mockResolvedValue({ count: 1 });
    }
    mocks.tx.user.update.mockResolvedValue(target);
  });

  afterEach(() => {
    vi.useRealTimers();
    delete process.env.ADMIN_EMAILS;
    delete process.env.ADMIN_EMAIL;
  });

  it("creates server-derived evidence with a 24-hour dueAt and alerts without content", async () => {
    const result = await createUserContentReport(reporter.id, target.id, {
      reason: "harassment",
      details: "Repeated insults",
      context: { type: "profile" }
    });

    expect(result).toEqual({
      id: "report-1",
      status: "pending",
      createdAt: now.toISOString(),
      dueAt: new Date(now.getTime() + 86_400_000).toISOString()
    });
    expect(mocks.tx.contentReport.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        reporterEmail: reporter.email,
        reportedEmail: target.email,
        contextSnapshot: expect.objectContaining({ userId: target.id, bio: profile.bio }),
        dueAt: new Date(now.getTime() + 86_400_000)
      })
    });
    expect(mocks.sendAlert).toHaveBeenCalledWith({
      reportId: "report-1",
      dueAt: new Date(now.getTime() + 86_400_000),
      origin: "report"
    });
  });

  it("snapshots server-derived chat attachment metadata and moderator URLs", async () => {
    mocks.tx.chatMessage.findFirst.mockResolvedValue({
      id: "message-1",
      matchId: "match-1",
      gameRequestId: null,
      text: "",
      createdAt: now,
      attachments: [{
        position: 0,
        asset: {
          id: "asset-1",
          mimeType: "image/jpeg",
          byteSize: 2048,
          originalName: "evidence.jpg",
          createdAt: now
        }
      }]
    });

    await createUserContentReport(reporter.id, target.id, {
      reason: "harassment",
      context: { type: "chat", id: "message-1" }
    });

    expect(mocks.tx.contentReport.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        contentType: "chat_message",
        contextId: "message-1",
        contextSnapshot: expect.objectContaining({
          attachments: [{
            position: 0,
            assetId: "asset-1",
            url: "/chat-media/asset-1",
            mimeType: "image/jpeg",
            byteSize: 2048,
            originalName: "evidence.jpg",
            createdAt: now.toISOString()
          }]
        })
      })
    });
  });

  it("rejects self-report and missing targets", async () => {
    await expect(createUserContentReport(reporter.id, reporter.id, { reason: "spam" })).rejects.toThrow("SELF_REPORT_FORBIDDEN");
    mocks.tx.user.findUnique.mockResolvedValueOnce(reporter).mockResolvedValueOnce(null);
    await expect(createUserContentReport(reporter.id, "missing", { reason: "spam" })).rejects.toThrow("REPORTED_USER_NOT_FOUND");
  });

  it("makes block reporting idempotent and sends the alert only for a newly created report", async () => {
    const existing = reportRecord({ origin: "block", blockId: "block-1" });
    mocks.tx.contentReport.findUnique.mockResolvedValueOnce(null).mockResolvedValueOnce(existing);

    await blockUserAndReport(reporter.id, target.id, {});
    await blockUserAndReport(reporter.id, target.id, {});

    expect(mocks.tx.block.upsert).toHaveBeenCalledTimes(2);
    expect(mocks.tx.match.updateMany).toHaveBeenCalledTimes(2);
    expect(mocks.tx.contentReport.create).toHaveBeenCalledTimes(1);
    expect(mocks.sendAlert).toHaveBeenCalledTimes(1);
    expect(mocks.tx.$queryRaw).toHaveBeenCalledTimes(2);
  });

  it("dismisses with optimistic locking without deactivating the target", async () => {
    mocks.tx.contentReport.findUnique.mockResolvedValue(reportRecord());
    await resolveAdminContentReport(
      { id: "admin-1", email: "moderator@example.com" },
      "report-1",
      { status: "dismissed", resolutionNote: "Нарушение не подтверждено", expectedUpdatedAt: now.toISOString() }
    );
    expect(mocks.tx.contentReport.updateMany).toHaveBeenCalledWith({
      where: { id: "report-1", status: "pending", updatedAt: now },
      data: expect.objectContaining({ status: "dismissed", reviewedByEmail: "moderator@example.com" })
    });
    expect(mocks.tx.user.update).not.toHaveBeenCalled();
  });

  it("rejects stale decisions before changing content", async () => {
    mocks.tx.contentReport.findUnique.mockResolvedValue(reportRecord({ updatedAt: new Date("2026-08-24T11:00:00.000Z") }));
    await expect(resolveAdminContentReport(
      { id: "admin-1", email: "moderator@example.com" },
      "report-1",
      { status: "actioned", resolutionNote: "Нарушение подтверждено", expectedUpdatedAt: now.toISOString() }
    )).rejects.toThrow("STALE_CONTENT_REPORT");
    expect(mocks.tx.user.update).not.toHaveBeenCalled();
  });

  it("protects the reviewing and configured admin accounts from actioning", async () => {
    mocks.tx.contentReport.findUnique.mockResolvedValue(reportRecord({ reportedUserId: "admin-1" }));
    mocks.tx.user.findUnique.mockResolvedValue({ id: "admin-1", email: "moderator@example.com" });
    await expect(resolveAdminContentReport(
      { id: "admin-1", email: "moderator@example.com" },
      "report-1",
      { status: "actioned", resolutionNote: "Нарушение подтверждено", expectedUpdatedAt: now.toISOString() }
    )).rejects.toThrow("ADMIN_TARGET_DEACTIVATION_FORBIDDEN");

    process.env.ADMIN_EMAILS = "protected@example.com";
    mocks.tx.contentReport.findUnique.mockResolvedValue(reportRecord());
    mocks.tx.user.findUnique.mockResolvedValue({ id: target.id, email: "protected@example.com" });
    await expect(resolveAdminContentReport(
      { id: "admin-2", email: "moderator@example.com" },
      "report-1",
      { status: "actioned", resolutionNote: "Нарушение подтверждено", expectedUpdatedAt: now.toISOString() }
    )).rejects.toThrow("ADMIN_TARGET_DEACTIVATION_FORBIDDEN");
    expect(mocks.tx.user.update).not.toHaveBeenCalled();
  });

  it("actioning removes UGC and revokes active capabilities atomically", async () => {
    mocks.tx.contentReport.findUnique.mockResolvedValue(reportRecord());
    mocks.tx.user.findUnique.mockResolvedValue(target);
    mocks.prisma.contentReport.findUnique.mockResolvedValue(reportRecord({ status: "actioned" }));
    await resolveAdminContentReport(
      { id: "admin-1", email: "moderator@example.com" },
      "report-1",
      { status: "actioned", resolutionNote: "Подтверждено модератором", expectedUpdatedAt: now.toISOString() }
    );
    expect(mocks.tx.user.update).toHaveBeenCalledWith({
      where: { id: target.id },
      data: expect.objectContaining({ accountStatus: "deactivated", name: null, bio: null, isLookingForGame: false })
    });
    expect(mocks.tx.session.deleteMany).toHaveBeenCalledWith({ where: { userId: target.id } });
    expect(mocks.tx.pushDevice.updateMany).toHaveBeenCalledWith({
      where: { userId: target.id, isActive: true },
      data: { isActive: false }
    });
    expect(mocks.tx.chatMessage.updateMany).toHaveBeenCalledWith({
      where: { senderUserId: target.id },
      data: { text: "Сообщение удалено модератором" }
    });
  });
});
