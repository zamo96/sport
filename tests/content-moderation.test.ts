import { describe, expect, it, vi } from "vitest";

import { isPublicTextAllowed, objectionableTextReason } from "@/lib/content-moderation";
import {
  blockUserSchema,
  createContentReportSchema,
  createGameSearchResponseSchema,
  createGameSearchSchema,
  messageSchema,
  updateMeSchema
} from "@/lib/validators";
import { hasBlockBetweenUsers } from "@/server/account-status";

describe("objectionable content filter", () => {
  it("rejects explicit abuse and credible threats in public UGC", () => {
    expect(objectionableTextReason("Я убью тебя после игры")).toBe("credible_threat");
    expect(isPublicTextAllowed("fuck")).toBe(false);
    expect(messageSchema.safeParse({ text: "ты еблан" }).success).toBe(false);
    expect(createGameSearchResponseSchema.safeParse({ message: "Я убью тебя" }).success).toBe(false);
  });

  it("does not flag normal sport, location, or name text", () => {
    const safeExamples = [
      "Ищу партнёра для тенниса вечером",
      "Играю в Санкт-Петербурге, уровень 4",
      "После работы могу с 19:00",
      "Сергей Хуйлов",
      "Люблю интенсивные тренировки"
    ];
    for (const text of safeExamples) expect(isPublicTextAllowed(text)).toBe(true);
  });

  it("applies moderation to profile name and bio", () => {
    const result = updateMeSchema.safeParse({ name: "Еблан", bio: "обычный профиль" });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.some((issue) => issue.path[0] === "name" && issue.message.includes("недопустимые"))).toBe(true);
    }
  });

  it("rejects objectionable public custom venue text", () => {
    const result = createGameSearchSchema.safeParse({
      preferredDays: ["monday"],
      preferredTimeRanges: ["evening"],
      sport: "tennis",
      format: "singles",
      customVenueTitle: "fuck"
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.some((issue) => issue.path[0] === "customVenueTitle")).toBe(true);
    }
  });
});

describe("content report contracts", () => {
  it("accepts the frozen report payload and rejects untrusted context fields", () => {
    expect(createContentReportSchema.safeParse({
      reason: "harassment",
      details: "Оскорбления в переписке",
      context: { type: "chat", id: "message-1" }
    }).success).toBe(true);
    expect(createContentReportSchema.safeParse({
      reason: "harassment",
      context: { type: "chat", id: "message-1", snapshot: "client controlled" }
    }).success).toBe(false);
  });

  it("keeps block requests backward compatible with an empty body", () => {
    expect(blockUserSchema.safeParse({}).success).toBe(true);
  });
});

describe("blocked interaction lookup", () => {
  it("checks both block directions", async () => {
    const findFirst = vi.fn().mockResolvedValue({ id: "block-1" });
    await expect(hasBlockBetweenUsers({ block: { findFirst } } as never, "a", "b")).resolves.toBe(true);
    expect(findFirst).toHaveBeenCalledWith({
      where: { OR: [{ blockerUserId: "a", blockedUserId: "b" }, { blockerUserId: "b", blockedUserId: "a" }] },
      select: { id: true }
    });
  });
});
