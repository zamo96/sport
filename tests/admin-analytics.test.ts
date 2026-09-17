import { describe, expect, it } from "vitest";
import {
  analyticsJournalCsv, analyticsPeriod, analyticsRate, buildAnalyticsFunnel,
  escapeAnalyticsCsvCell, normalizeAnalyticsFilters
} from "@/lib/admin-analytics";

describe("analytics windows and filters", () => {
  it("uses bounded calendar windows and rejects nonfinite pagination", () => {
    expect(normalizeAnalyticsFilters({ days: 400, page: NaN })).toEqual({ days: 30, page: 1, userId: "", eventType: "" });
    expect(normalizeAnalyticsFilters({ days: 7, page: -2, userId: " user-id ", eventType: " swipe " })).toEqual({ days: 7, page: 1, userId: "user-id", eventType: "swipe" });
    expect(normalizeAnalyticsFilters({ days: 90, page: 2.9 }).page).toBe(2);
  });
  it("keeps UTC day boundaries stable across a month and daylight saving change", () => {
    const period = analyticsPeriod(7, new Date("2026-11-02T15:30:00Z"));
    expect(period.from.toISOString()).toBe("2026-10-27T00:00:00.000Z");
    expect(period.to.toISOString()).toBe("2026-11-02T15:30:00.000Z");
  });
  it("distinguishes absent cohorts from zero conversions", () => {
    expect(analyticsRate(0, 0)).toBeNull();
    expect(analyticsRate(0, 5)).toBe(0);
    expect(analyticsRate(1, 3)).toBe(33.3);
    expect(buildAnalyticsFunnel([5, 4, 3, 2, 1])[4]).toMatchObject({ users: 1, dropOff: 1, conversionFromPrevious: 50, conversionFromRegistration: 20 });
    expect(buildAnalyticsFunnel([0, 0, 0, 0, 0])[4].conversionFromPrevious).toBeNull();
  });
});

describe("analytics CSV", () => {
  it.each(["=HYPERLINK(\"https://example.com\")", "+SUM(A1)", "-1+2", "@SUM(A1)", "  =1+2", "\t=1+2", "\nhello"])("neutralizes spreadsheet formulas %j", (value) => {
    expect(escapeAnalyticsCsvCell(value).startsWith('"\'')).toBe(true);
  });
  it("preserves Cyrillic and quotes multiline cells", () => {
    expect(escapeAnalyticsCsvCell('Матвей, "Игрок"\nстрока')).toBe('"Матвей, ""Игрок""\nстрока"');
  });
  it("exports metadata and a visible truncation warning without silently losing rows", () => {
    const csv = analyticsJournalCsv([{
      id: "event-1", userId: "user-1", userName: "=1+1", userEmail: "test@example.com",
      type: "search_created", label: "Поиск", entityType: "game_search", entityId: "search-1",
      context: { sport: "tennis" }, createdAt: new Date("2026-09-05T10:00:00Z")
    }], true);
    expect(csv.startsWith("\uFEFF")).toBe(true);
    expect(csv).toContain("2026-09-05T10:00:00.000Z");
    expect(csv).toContain('"\'=1+1"');
    expect(csv).toContain("EXPORT_TRUNCATED");
    expect(csv).toContain("10000");
  });
});
