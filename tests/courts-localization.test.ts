import { describe, expect, it } from "vitest";

import {
  courtsMessages,
  formatCourtsDistance,
  formatCourtsRadius,
  formatCourtsVenueCount,
  translateCourts
} from "@/lib/i18n/web/courts";

describe("courts web localization", () => {
  it("keeps English and Russian message keys in exact parity", () => {
    expect(Object.keys(courtsMessages.ru).sort()).toEqual(Object.keys(courtsMessages.en).sort());
  });

  it("translates the page, filters, cards, errors, and accessibility labels", () => {
    expect(translateCourts("en", "courts.page.eyebrow")).toBe("Sports venues");
    expect(translateCourts("ru", "courts.page.eyebrow")).toBe("Спортивные центры");
    expect(translateCourts("en", "courts.search.placeholder")).toContain("club");
    expect(translateCourts("en", "courts.card.propose")).toBe("Propose a game here");
    expect(translateCourts("ru", "courts.map.loadError")).toBe("Не удалось загрузить Яндекс Карты.");
    expect(translateCourts("en", "courts.alphabet.jump", { letter: "T" })).toBe(
      "Go to clubs starting with T"
    );
  });

  it("formats venue counts with locale-aware plural forms", () => {
    expect(formatCourtsVenueCount("en", 1)).toBe("1 venue");
    expect(formatCourtsVenueCount("en", 2)).toBe("2 venues");
    expect(formatCourtsVenueCount("ru", 1)).toBe("1 центр");
    expect(formatCourtsVenueCount("ru", 2)).toBe("2 центра");
    expect(formatCourtsVenueCount("ru", 5)).toBe("5 центров");
  });

  it("formats distance and radius units for the active locale", () => {
    expect(formatCourtsDistance("en", null)).toBe("Nearby");
    expect(formatCourtsDistance("ru", 0.45)).toBe("450 м");
    expect(formatCourtsDistance("en", 1.25)).toBe("1.3 km");
    expect(formatCourtsDistance("ru", 1.25)).toBe("1,3 км");
    expect(formatCourtsRadius("en", 10)).toBe("10 km");
  });
});
