import { describe, expect, it } from "vitest";

import { SPORT_OPTIONS } from "@/lib/constants";
import {
  ENGLISH_SPORT_LEVEL_GUIDES,
  getLocalizedSportLevelGuide
} from "@/lib/i18n/web/sport-level-guide-content";
import { SPORT_LEVEL_GUIDES } from "@/lib/sport-level-guides";

const EXPECTED_LEVELS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

describe("sport level guide localization", () => {
  it("keeps all sport codes and levels in exact EN/RU parity", () => {
    expect(Object.keys(ENGLISH_SPORT_LEVEL_GUIDES)).toEqual([...SPORT_OPTIONS]);
    expect(Object.keys(SPORT_LEVEL_GUIDES)).toEqual([...SPORT_OPTIONS]);

    for (const sport of SPORT_OPTIONS) {
      const englishGuide = ENGLISH_SPORT_LEVEL_GUIDES[sport];
      const russianGuide = SPORT_LEVEL_GUIDES[sport];

      expect(englishGuide).toHaveLength(10);
      expect(russianGuide).toHaveLength(10);
      expect(englishGuide.map(({ level }) => level)).toEqual(EXPECTED_LEVELS);
      expect(russianGuide.map(({ level }) => level)).toEqual(EXPECTED_LEVELS);
      expect(englishGuide.map(({ level }) => level)).toEqual(russianGuide.map(({ level }) => level));
    }
  });

  it("provides complete English presentation content for every sport and level", () => {
    const descriptions = new Set<string>();

    for (const sport of SPORT_OPTIONS) {
      for (const entry of ENGLISH_SPORT_LEVEL_GUIDES[sport]) {
        expect(entry.title.trim()).not.toBe("");
        expect(entry.description.trim()).not.toBe("");
        expect(entry.title).not.toMatch(/[А-Яа-яЁё]/);
        expect(entry.description).not.toMatch(/[А-Яа-яЁё]/);
        descriptions.add(entry.description);
      }
    }

    expect(descriptions.size).toBe(SPORT_OPTIONS.length * EXPECTED_LEVELS.length);
  });

  it("selects exact sport-specific content for the active locale", () => {
    for (const sport of SPORT_OPTIONS) {
      expect(getLocalizedSportLevelGuide("ru", sport)).toBe(SPORT_LEVEL_GUIDES[sport]);
      expect(getLocalizedSportLevelGuide("en", sport)).toBe(ENGLISH_SPORT_LEVEL_GUIDES[sport]);
    }

    expect(getLocalizedSportLevelGuide("en", "tennis")[0].description).toContain("net");
    expect(getLocalizedSportLevelGuide("en", "running")[0].description).toContain("walking");
    expect(getLocalizedSportLevelGuide("en", "padel")[0].description).toContain("glass");
  });
});
