import { describe, expect, it } from "vitest";

import { resolveHotDigestSlot } from "@/server/hot-search-digest";

describe("hot digest slots per player timezone", () => {
  it("keeps the Moscow behaviour as the default", () => {
    const midday = resolveHotDigestSlot(new Date("2026-07-01T09:05:00.000Z"));
    expect(midday?.slotKey).toBe("2026-07-01:midday");
    expect(midday?.since.toISOString()).toBe("2026-06-30T15:00:00.000Z");

    const evening = resolveHotDigestSlot(new Date("2026-07-01T15:30:00.000Z"));
    expect(evening?.slotKey).toBe("2026-07-01:evening");
    expect(evening?.since.toISOString()).toBe("2026-07-01T09:00:00.000Z");
  });

  it("gives every player their own noon instead of a shared Moscow one", () => {
    // 08:05Z — это 12:05 в Дубае, 11:05 в Москве и 09:05 в Лондоне.
    const noonInDubai = new Date("2026-07-01T08:05:00.000Z");
    expect(resolveHotDigestSlot(noonInDubai, "Asia/Dubai")?.label).toBe("midday");
    expect(resolveHotDigestSlot(noonInDubai, "Europe/Moscow")).toBeNull();
    expect(resolveHotDigestSlot(noonInDubai, "Europe/London")).toBeNull();

    // Каждый получает своё окно на час-другой позже.
    expect(resolveHotDigestSlot(new Date("2026-07-01T09:05:00.000Z"), "Europe/Moscow")?.label).toBe("midday");
    expect(resolveHotDigestSlot(new Date("2026-07-01T11:05:00.000Z"), "Europe/London")?.label).toBe("midday");
  });

  it("uses the local calendar day in the slot key", () => {
    // 2026-07-01T19:30Z: в Новосибирске уже 2 июля, вечернее окно закрыто.
    expect(resolveHotDigestSlot(new Date("2026-07-01T19:30:00.000Z"), "Asia/Novosibirsk")).toBeNull();
    expect(resolveHotDigestSlot(new Date("2026-07-01T11:30:00.000Z"), "Asia/Novosibirsk")?.slotKey).toBe(
      "2026-07-01:evening"
    );
  });

  it("stays silent outside both windows", () => {
    for (const hour of [0, 8, 11, 15, 17, 21, 23]) {
      const instant = new Date(Date.UTC(2026, 6, 1, hour - 3, 0, 0));
      expect(resolveHotDigestSlot(instant, "Europe/Moscow")).toBeNull();
    }
  });

  it("covers the whole three-hour window", () => {
    for (const hour of [12, 13, 14, 18, 19, 20]) {
      const instant = new Date(Date.UTC(2026, 6, 1, hour - 3, 0, 0));
      expect(resolveHotDigestSlot(instant, "Europe/Moscow")).not.toBeNull();
    }
  });

  it("anchors the search window to the previous slot", () => {
    // 17:30Z = 18:30 по Лондону летом.
    const evening = resolveHotDigestSlot(new Date("2026-07-01T17:30:00.000Z"), "Europe/London");
    expect(evening?.slotKey).toBe("2026-07-01:evening");
    // Лондон летом: полдень = 11:00Z.
    expect(evening?.since.toISOString()).toBe("2026-07-01T11:00:00.000Z");
  });
});
