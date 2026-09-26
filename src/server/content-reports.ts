import {
  AccountStatus,
  ContentReportOrigin,
  ContentReportReason,
  ContentReportStatus,
  ContentReportType,
  GameReportVisibility,
  MatchStatus,
  Prisma,
  type User
} from "@prisma/client";

import { sendContentReportAlert } from "@/lib/email";
import { isAdminUser } from "@/lib/admin";
import { prisma } from "@/lib/prisma";
import type {
  AdminContentReportsQuery,
  CreateContentReportInput,
  ResolveContentReportInput
} from "@/lib/validators";
import { lockActiveUsersForMutation } from "@/server/account-status";
import { accountContact } from "@/lib/account-contact";

const REPORT_SLA_MS = 24 * 60 * 60 * 1000;
const REMOVED_MESSAGE = "Сообщение удалено модератором";

type Db = Prisma.TransactionClient | typeof prisma;

export function serializeContentReportSummary(report: {
  id: string;
  status: ContentReportStatus;
  createdAt: Date;
  dueAt: Date;
}) {
  return {
    id: report.id,
    status: report.status,
    createdAt: report.createdAt.toISOString(),
    dueAt: report.dueAt.toISOString()
  };
}

function publicProfileSnapshot(user: {
  id: string;
  name: string | null;
  bio: string | null;
  avatarUrl: string | null;
  profilePhotoUrls: Prisma.JsonValue;
  profileVideoUrls: Prisma.JsonValue;
}) {
  return {
    userId: user.id,
    name: user.name,
    bio: user.bio,
    avatarUrl: user.avatarUrl,
    profilePhotoUrls: user.profilePhotoUrls,
    profileVideoUrls: user.profileVideoUrls
  } satisfies Prisma.JsonObject;
}

async function deriveContextSnapshot(
  db: Db,
  targetUserId: string,
  context: CreateContentReportInput["context"]
): Promise<{ contentType: ContentReportType; contextId: string | null; contextSnapshot: Prisma.InputJsonValue }> {
  if (context?.type === "chat" && context.id) {
    const directMessage = await db.chatMessage.findFirst({
      where: { id: context.id, senderUserId: targetUserId },
      select: {
        id: true,
        matchId: true,
        gameRequestId: true,
        text: true,
        createdAt: true,
        attachments: {
          orderBy: { position: "asc" },
          select: {
            position: true,
            asset: { select: { id: true, mimeType: true, byteSize: true, originalName: true, createdAt: true } }
          }
        }
      }
    });
    if (directMessage) {
      return {
        contentType: ContentReportType.chat_message,
        contextId: directMessage.id,
        contextSnapshot: {
          ...directMessage,
          createdAt: directMessage.createdAt.toISOString(),
          attachments: directMessage.attachments.map(({ position, asset }) => ({
            position,
            assetId: asset.id,
            url: `/chat-media/${asset.id}`,
            mimeType: asset.mimeType,
            byteSize: asset.byteSize,
            originalName: asset.originalName,
            createdAt: asset.createdAt.toISOString()
          }))
        }
      };
    }

    const lobbyMessage = await db.gameSearchMessage.findFirst({
      where: { id: context.id, senderUserId: targetUserId },
      select: {
        id: true,
        gameSearchId: true,
        text: true,
        createdAt: true,
        attachments: {
          orderBy: { position: "asc" },
          select: {
            position: true,
            asset: { select: { id: true, mimeType: true, byteSize: true, originalName: true, createdAt: true } }
          }
        }
      }
    });
    if (lobbyMessage) {
      return {
        contentType: ContentReportType.game_search_message,
        contextId: lobbyMessage.id,
        contextSnapshot: {
          ...lobbyMessage,
          createdAt: lobbyMessage.createdAt.toISOString(),
          attachments: lobbyMessage.attachments.map(({ position, asset }) => ({
            position,
            assetId: asset.id,
            url: `/chat-media/${asset.id}`,
            mimeType: asset.mimeType,
            byteSize: asset.byteSize,
            originalName: asset.originalName,
            createdAt: asset.createdAt.toISOString()
          }))
        }
      };
    }
  }

  const target = await db.user.findUniqueOrThrow({
    where: { id: targetUserId },
    select: {
      id: true,
      name: true,
      bio: true,
      avatarUrl: true,
      profilePhotoUrls: true,
      profileVideoUrls: true
    }
  });
  return {
    contentType: ContentReportType.profile,
    contextId: target.id,
    contextSnapshot: publicProfileSnapshot(target)
  };
}

async function alertBestEffort(report: { id: string; dueAt: Date; origin: ContentReportOrigin }) {
  try {
    await sendContentReportAlert({ reportId: report.id, dueAt: report.dueAt, origin: report.origin });
  } catch (error) {
    console.error("[moderation] Failed to send report alert", {
      reportId: report.id,
      error: error instanceof Error ? error.message : "unknown"
    });
  }
}

export async function createUserContentReport(
  reporterUserId: string,
  reportedUserId: string,
  input: CreateContentReportInput
) {
  if (reporterUserId === reportedUserId) throw new Error("SELF_REPORT_FORBIDDEN");

  const report = await prisma.$transaction(async (tx) => {
    const [reporter, target] = await Promise.all([
      tx.user.findUnique({ where: { id: reporterUserId }, select: { id: true, email: true, phone: true, name: true } }),
      tx.user.findUnique({ where: { id: reportedUserId }, select: { id: true, email: true, phone: true, name: true } })
    ]);
    if (!reporter) throw new Error("UNAUTHORIZED");
    if (!target) throw new Error("REPORTED_USER_NOT_FOUND");
    const derived = await deriveContextSnapshot(tx, reportedUserId, input.context);
    const now = new Date();
    return tx.contentReport.create({
      data: {
        reporterUserId,
        reporterEmail: accountContact(reporter),
        reporterName: reporter.name,
        reportedUserId,
        reportedEmail: accountContact(target),
        reportedName: target.name,
        origin: ContentReportOrigin.report,
        reason: input.reason,
        details: input.details || null,
        ...derived,
        dueAt: new Date(now.getTime() + REPORT_SLA_MS)
      }
    });
  });

  await alertBestEffort(report);
  return serializeContentReportSummary(report);
}

export async function blockUserAndReport(
  reporterUserId: string,
  reportedUserId: string,
  input: Partial<CreateContentReportInput>
) {
  if (reporterUserId === reportedUserId) throw new Error("SELF_BLOCK_FORBIDDEN");

  const result = await prisma.$transaction(async (tx) => {
    const locked = await lockActiveUsersForMutation(tx, [reporterUserId, reportedUserId]);
    if (!locked.has(reporterUserId)) throw new Error("UNAUTHORIZED");
    if (!locked.has(reportedUserId)) throw new Error("REPORTED_USER_NOT_FOUND");
    const [reporter, target] = await Promise.all([
      tx.user.findUnique({ where: { id: reporterUserId }, select: { id: true, email: true, phone: true, name: true } }),
      tx.user.findUnique({ where: { id: reportedUserId }, select: { id: true, email: true, phone: true, name: true } })
    ]);
    if (!reporter) throw new Error("UNAUTHORIZED");
    if (!target) throw new Error("REPORTED_USER_NOT_FOUND");

    const block = await tx.block.upsert({
      where: { blockerUserId_blockedUserId: { blockerUserId: reporterUserId, blockedUserId: reportedUserId } },
      create: { blockerUserId: reporterUserId, blockedUserId: reportedUserId },
      update: {}
    });
    await tx.match.updateMany({
      where: {
        OR: [
          { user1Id: reporterUserId, user2Id: reportedUserId },
          { user1Id: reportedUserId, user2Id: reporterUserId }
        ]
      },
      data: { status: MatchStatus.archived }
    });
    const existing = await tx.contentReport.findUnique({ where: { blockId: block.id } });
    if (existing) return { report: existing, created: false };

    const derived = await deriveContextSnapshot(tx, reportedUserId, input.context);
    const now = new Date();
    const created = await tx.contentReport.create({
      data: {
        reporterUserId,
        reporterEmail: accountContact(reporter),
        reporterName: reporter.name,
        reportedUserId,
        reportedEmail: accountContact(target),
        reportedName: target.name,
        blockId: block.id,
        origin: ContentReportOrigin.block,
        reason: input.reason ?? ContentReportReason.abusive_behavior,
        details: input.details || null,
        ...derived,
        dueAt: new Date(now.getTime() + REPORT_SLA_MS)
      }
    });

    return { report: created, created: true };
  });

  if (result.created) await alertBestEffort(result.report);
  return serializeContentReportSummary(result.report);
}

const reportInclude = {
  reporterUser: { select: { id: true, email: true, phone: true, name: true } },
  reportedUser: {
    select: { id: true, email: true, name: true, accountStatus: true, avatarUrl: true, updatedAt: true }
  },
  reviewedByUser: { select: { id: true, email: true, phone: true, name: true } }
} satisfies Prisma.ContentReportInclude;

export async function listAdminContentReports(query: AdminContentReportsQuery) {
  const where: Prisma.ContentReportWhereInput = {
    ...(query.status === "all" ? {} : { status: query.status }),
    ...(query.origin === "all" ? {} : { origin: query.origin }),
    ...(query.q
      ? {
          OR: [
            { id: { contains: query.q, mode: "insensitive" } },
            { reporterEmail: { contains: query.q, mode: "insensitive" } },
            { reporterName: { contains: query.q, mode: "insensitive" } },
            { reportedEmail: { contains: query.q, mode: "insensitive" } },
            { reportedName: { contains: query.q, mode: "insensitive" } }
          ]
        }
      : {})
  };
  const skip = (query.page - 1) * query.limit;
  const [total, reports] = await prisma.$transaction([
    prisma.contentReport.count({ where }),
    prisma.contentReport.findMany({
      where,
      skip,
      take: query.limit,
      orderBy: [{ status: "asc" }, { dueAt: "asc" }, { createdAt: "desc" }],
      include: reportInclude
    })
  ]);
  return {
    reports,
    pagination: {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.ceil(total / query.limit)
    }
  };
}

export async function getAdminContentReport(reportId: string) {
  const report = await prisma.contentReport.findUnique({ where: { id: reportId }, include: reportInclude });
  if (!report) throw new Error("CONTENT_REPORT_NOT_FOUND");
  return { report };
}

export async function resolveAdminContentReport(
  actor: Pick<User, "id" | "email">,
  reportId: string,
  input: ResolveContentReportInput
) {
  await prisma.$transaction(async (tx) => {
    const current = await tx.contentReport.findUnique({ where: { id: reportId } });
    if (!current) throw new Error("CONTENT_REPORT_NOT_FOUND");
    if (current.updatedAt.getTime() !== new Date(input.expectedUpdatedAt).getTime() || current.status !== ContentReportStatus.pending) {
      throw new Error("STALE_CONTENT_REPORT");
    }

    if (input.status === ContentReportStatus.actioned) {
      if (!current.reportedUserId) throw new Error("REPORTED_USER_NOT_FOUND");
      const target = await tx.user.findUnique({ where: { id: current.reportedUserId }, select: { id: true, email: true } });
      if (!target) throw new Error("REPORTED_USER_NOT_FOUND");
      if (target.id === actor.id || isAdminUser(target)) throw new Error("ADMIN_TARGET_DEACTIVATION_FORBIDDEN");
      await removeUserGeneratedContentAndDeactivate(tx, current.reportedUserId, input.resolutionNote);
    }

    const updated = await tx.contentReport.updateMany({
      where: { id: current.id, status: ContentReportStatus.pending, updatedAt: current.updatedAt },
      data: {
        status: input.status,
        resolutionNote: input.resolutionNote,
        reviewedAt: new Date(),
        reviewedByUserId: actor.id,
        reviewedByEmail: actor.email
      }
    });
    if (updated.count !== 1) throw new Error("STALE_CONTENT_REPORT");
  });
  return getAdminContentReport(reportId);
}

async function removeUserGeneratedContentAndDeactivate(
  tx: Prisma.TransactionClient,
  userId: string,
  resolutionNote: string
) {
  const now = new Date();
  await tx.user.update({
    where: { id: userId },
    data: {
      name: null,
      bio: null,
      avatarUrl: null,
      profilePhotoUrls: [],
      profileVideoUrls: [],
      isLookingForGame: false,
      accountStatus: AccountStatus.deactivated,
      deactivatedAt: now,
      deactivationReason: `Подтверждённая жалоба: ${resolutionNote}`
    }
  });
  await Promise.all([
    tx.session.deleteMany({ where: { userId } }),
    tx.pushDevice.updateMany({ where: { userId, isActive: true }, data: { isActive: false } }),
    tx.match.updateMany({ where: { OR: [{ user1Id: userId }, { user2Id: userId }] }, data: { status: MatchStatus.archived } }),
    tx.gameSearch.updateMany({
      where: { createdByUserId: userId },
      data: {
        isActive: false,
        status: "closed",
        comment: "",
        customVenueTitle: null,
        customVenueAddress: null,
        runningRoute: null,
        runningRoutePoints: Prisma.DbNull
      }
    }),
    tx.gameSearchResponse.updateMany({ where: { responderUserId: userId }, data: { message: "" } }),
    tx.regularPair.updateMany({ where: { createdByUserId: userId }, data: { comment: "" } }),
    tx.gameSearchSlotProposal.updateMany({
      where: { gameSearch: { createdByUserId: userId } },
      data: { comment: "" }
    }),
    tx.gameRequest.updateMany({ where: { createdByUserId: userId }, data: { comment: "" } }),
    tx.gameReport.updateMany({
      where: { createdByUserId: userId },
      data: { comment: "", visibility: GameReportVisibility.private }
    }),
    tx.gameReportPhoto.deleteMany({ where: { report: { createdByUserId: userId } } }),
    tx.personalActivity.updateMany({ where: { userId }, data: { comment: "", reportComment: null, videoUrls: [] } }),
    tx.personalActivityPhoto.deleteMany({ where: { activity: { userId } } }),
    tx.chatMessage.updateMany({ where: { senderUserId: userId }, data: { text: REMOVED_MESSAGE } }),
    tx.gameSearchMessage.updateMany({ where: { senderUserId: userId }, data: { text: REMOVED_MESSAGE } }),
    tx.chatMessageMedia.deleteMany({ where: { chatMessage: { senderUserId: userId } } }),
    tx.gameSearchMessageMedia.deleteMany({ where: { gameSearchMessage: { senderUserId: userId } } })
  ]);
}
