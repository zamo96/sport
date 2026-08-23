import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  DEFAULT_CITY,
  DISTRICT_MAP_AREAS,
  SAINT_PETERSBURG_DISTRICT_OPTIONS
} from "@/lib/constants";
import { buildGeneratedDemoUsers } from "../prisma/demo-simulator";

describe("demo simulator users", () => {
  it("keeps the Saint Petersburg district list aligned with the seed reference", () => {
    const referencePath = path.join(process.cwd(), "docs", "import", "districts-reference.csv");
    const referenceDistricts = readFileSync(referencePath, "utf8")
      .split(/\r?\n/)
      .slice(1)
      .map((line) => line.split(",", 1)[0]?.trim())
      .filter(Boolean);

    expect(referenceDistricts).toEqual([...SAINT_PETERSBURG_DISTRICT_OPTIONS]);
  });

  it("generates users only in referenced Saint Petersburg districts", () => {
    const users = buildGeneratedDemoUsers(50);
    const saintPetersburgDistricts = new Set<string>(SAINT_PETERSBURG_DISTRICT_OPTIONS);

    expect(users).toHaveLength(50);

    for (const user of users) {
      expect(user.city).toBe(DEFAULT_CITY);
      expect(typeof user.district).toBe("string");
      expect(saintPetersburgDistricts.has(user.district as string)).toBe(true);

      const area = DISTRICT_MAP_AREAS[user.district as string];
      expect(area).toBeDefined();
      expect(Number.isFinite(area.center.lat)).toBe(true);
      expect(Number.isFinite(area.center.lng)).toBe(true);
      expect(Number.isFinite(user.homeLat)).toBe(true);
      expect(Number.isFinite(user.homeLng)).toBe(true);
    }
  });
});
