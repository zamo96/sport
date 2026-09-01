import { describe, expect, it } from "vitest";

import {
  discoverMessages,
  formatDiscoverDistance,
  translateDiscoverReason
} from "@/lib/i18n/web/discover";

describe("discover localization", () => {
  it("keeps EN and RU catalogs in parity", () => {
    expect(Object.keys(discoverMessages.en).sort()).toEqual(Object.keys(discoverMessages.ru).sort());
  });

  it("localizes every server explainability reason shape", () => {
    expect(translateDiscoverReason("en", "Совпадает спорт: Большой теннис")).toBe("Matching sport: Tennis");
    expect(translateDiscoverReason("en", "Уровень рядом: 4–6")).toBe("Similar level: 4–6");
    expect(translateDiscoverReason("en", "Недалеко: 2.4 км")).toBe("Nearby: 2.4 km");
    expect(translateDiscoverReason("en", "Рядом по району")).toBe("Nearby area");
    expect(translateDiscoverReason("en", "Пересекается расписание")).toBe("Schedules overlap");
  });

  it("formats distance according to the selected locale", () => {
    expect(formatDiscoverDistance("en", 0.45)).toBe("450 m");
    expect(formatDiscoverDistance("en", 2.4)).toBe("2.4 km");
    expect(formatDiscoverDistance("ru", null)).toBe("рядом");
  });
});
