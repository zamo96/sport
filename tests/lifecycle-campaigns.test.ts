import { describe, expect, it } from "vitest";

import { DAY_OPTIONS } from "@/lib/constants";
import { translateServer } from "@/lib/i18n/server";
import { pluralKeySuffix } from "@/lib/i18n/server/notifications";
import { CAMPAIGNS, LIFECYCLE_CAMPAIGN_KEYS } from "@/server/notification-campaigns";
import { resolveTomorrowSlot } from "@/server/lifecycle-campaigns";

// 2026-09-02 — среда, значит «завтра» это четверг.
const wednesdayNoon = new Date("2026-09-02T09:00:00.000Z");

describe("training nudge slot", () => {
  it("picks tomorrow's free slot from the profile", () => {
    expect(
      resolveTomorrowSlot({ thursday: ["evening"] }, "Europe/Moscow", wednesdayNoon)
    ).toEqual({ day: "thursday", timeRange: "evening" });
  });

  it("stays silent when tomorrow is not marked free", () => {
    expect(resolveTomorrowSlot({ saturday: ["day"] }, "Europe/Moscow", wednesdayNoon)).toBeNull();
    expect(resolveTomorrowSlot({ thursday: [] }, "Europe/Moscow", wednesdayNoon)).toBeNull();
  });

  it("wraps from sunday to monday", () => {
    const sunday = new Date("2026-09-06T09:00:00.000Z");
    expect(resolveTomorrowSlot({ monday: ["morning"] }, "Europe/Moscow", sunday)).toEqual({
      day: "monday",
      timeRange: "morning"
    });
  });

  it("uses the player's own calendar", () => {
    // 21:30Z в среду — это уже четверг в Москве, значит «завтра» пятница.
    const lateEvening = new Date("2026-09-02T21:30:00.000Z");
    expect(resolveTomorrowSlot({ friday: ["evening"] }, "Europe/Moscow", lateEvening)).toEqual({
      day: "friday",
      timeRange: "evening"
    });
    expect(resolveTomorrowSlot({ thursday: ["evening"] }, "Europe/London", lateEvening)).toEqual({
      day: "thursday",
      timeRange: "evening"
    });
  });

  it("ignores malformed availability", () => {
    expect(resolveTomorrowSlot(null, "Europe/Moscow", wednesdayNoon)).toBeNull();
    expect(resolveTomorrowSlot(["thursday"], "Europe/Moscow", wednesdayNoon)).toBeNull();
    expect(resolveTomorrowSlot("thursday", "Europe/Moscow", wednesdayNoon)).toBeNull();
    expect(resolveTomorrowSlot({ thursday: ["whenever"] }, "Europe/Moscow", wednesdayNoon)).toBeNull();
    expect(resolveTomorrowSlot({ thursday: [42] }, "Europe/Moscow", wednesdayNoon)).toBeNull();
  });
});

describe("campaign registry", () => {
  it("registers every lifecycle campaign the runner sends", () => {
    for (const key of [
      "onboarding_incomplete",
      "first_players_ready",
      "new_players_arrived",
      "likes_waiting",
      "training_nudge",
      "win_back",
      "hot_search_digest"
    ] as const) {
      expect(CAMPAIGNS[key]).toBeDefined();
      expect(LIFECYCLE_CAMPAIGN_KEYS).toContain(key);
    }
  });

  it("keeps every campaign behind a notification toggle", () => {
    for (const key of LIFECYCLE_CAMPAIGN_KEYS) {
      expect(CAMPAIGNS[key].preferenceKey).toMatch(/^notification/);
      expect(CAMPAIGNS[key].cooldownHours).toBeGreaterThan(0);
    }
  });
});

describe("campaign copy", () => {
  it("agrees with the count in russian", () => {
    const body = (count: number) =>
      translateServer("ru", `push.newPlayers.body.${pluralKeySuffix("ru", count)}`, { count });

    expect(body(1)).toContain("1 новый игрок");
    expect(body(3)).toContain("3 новых игрока");
    expect(body(7)).toContain("7 новых игроков");
  });

  it("renders a full weekday with the right preposition", () => {
    const nudge = (locale: "ru" | "en", day: (typeof DAY_OPTIONS)[number]) =>
      translateServer(locale, "push.trainingNudge.body", {
        day: translateServer(locale, `push.day.${day}`)
      });

    expect(nudge("ru", "tuesday")).toContain("во вторник");
    expect(nudge("ru", "wednesday")).toContain("в среду");
    expect(nudge("ru", "thursday")).toContain("в четверг");
    expect(nudge("en", "thursday")).toContain("on Thursday");
  });

  it("has a name for every weekday", () => {
    for (const day of DAY_OPTIONS) {
      expect(translateServer("ru", `push.day.${day}`)).not.toContain("push.day");
      expect(translateServer("en", `push.day.${day}`)).not.toContain("push.day");
    }
  });
});
