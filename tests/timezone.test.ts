import { describe, expect, it } from "vitest";

import {
  DEFAULT_TIMEZONE,
  getLocalDateParts,
  localDateTimeToUtc,
  resolveLocalHour,
  resolveTimezoneFromCoordinates,
  resolveTimezoneOrDefault
} from "@/lib/timezone";

describe("timezone from coordinates", () => {
  it("resolves real cities", () => {
    expect(resolveTimezoneFromCoordinates(55.7558, 37.6173)).toBe("Europe/Moscow");
    expect(resolveTimezoneFromCoordinates(25.2048, 55.2708)).toBe("Asia/Dubai");
    expect(resolveTimezoneFromCoordinates(51.5074, -0.1278)).toBe("Europe/London");
    expect(resolveTimezoneFromCoordinates(40.7128, -74.006)).toBe("America/New_York");
  });

  it("separates zones inside one country", () => {
    expect(resolveTimezoneFromCoordinates(59.9343, 30.3351)).toBe("Europe/Moscow");
    expect(resolveTimezoneFromCoordinates(55.0084, 82.9357)).toBe("Asia/Novosibirsk");
  });

  it("returns null for missing or impossible coordinates", () => {
    expect(resolveTimezoneFromCoordinates(null, null)).toBeNull();
    expect(resolveTimezoneFromCoordinates(55.75, undefined)).toBeNull();
    expect(resolveTimezoneFromCoordinates(Number.NaN, 37.61)).toBeNull();
    expect(resolveTimezoneFromCoordinates(120, 37.61)).toBeNull();
    expect(resolveTimezoneFromCoordinates(55.75, 500)).toBeNull();
  });

  it("falls back to the default zone when nothing resolves", () => {
    expect(resolveTimezoneOrDefault(null, null)).toBe(DEFAULT_TIMEZONE);
    expect(resolveTimezoneOrDefault(25.2048, 55.2708)).toBe("Asia/Dubai");
  });
});

describe("local date parts", () => {
  const instant = new Date("2026-09-02T21:30:00.000Z");

  it("reports the player's own calendar day and hour", () => {
    expect(getLocalDateParts("Europe/Moscow", instant)).toMatchObject({ dateKey: "2026-09-03", hour: 0 });
    expect(getLocalDateParts("Europe/London", instant)).toMatchObject({ dateKey: "2026-09-02", hour: 22 });
    expect(getLocalDateParts("America/New_York", instant)).toMatchObject({ dateKey: "2026-09-02", hour: 17 });
  });

  it("falls back to Moscow for empty and broken zones", () => {
    expect(resolveLocalHour(null, instant)).toBe(0);
    expect(resolveLocalHour("Not/AZone", instant)).toBe(0);
  });
});

describe("local time to utc", () => {
  it("accounts for daylight saving time", () => {
    expect(localDateTimeToUtc("Europe/London", 2026, 7, 1, 12).toISOString()).toBe("2026-07-01T11:00:00.000Z");
    expect(localDateTimeToUtc("Europe/London", 2026, 1, 15, 12).toISOString()).toBe("2026-01-15T12:00:00.000Z");
  });

  it("handles zones with fractional offsets", () => {
    expect(localDateTimeToUtc("Asia/Kolkata", 2026, 7, 1, 12).toISOString()).toBe("2026-07-01T06:30:00.000Z");
    expect(localDateTimeToUtc("Asia/Kathmandu", 2026, 7, 1, 12).toISOString()).toBe("2026-07-01T06:15:00.000Z");
  });

  it("keeps whole-hour zones exact", () => {
    expect(localDateTimeToUtc("Europe/Moscow", 2026, 7, 1, 18).toISOString()).toBe("2026-07-01T15:00:00.000Z");
    expect(localDateTimeToUtc("Asia/Novosibirsk", 2026, 7, 1, 12).toISOString()).toBe("2026-07-01T05:00:00.000Z");
  });
});
