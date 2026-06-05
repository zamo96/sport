import { describe, expect, it } from "vitest";

import { PlayFormat, Sport } from "@prisma/client";

import {
  getDefaultDurationMinutes,
  getDefaultPlayersNeeded,
  getSportFormatOptions,
  resolveFormatForSport
} from "@/lib/sport-playbook";

describe("sport playbook (canonical defaults)", () => {
  it("restricts formats by sport", () => {
    expect(getSportFormatOptions(Sport.padel)).toEqual([PlayFormat.doubles]);
    expect(getSportFormatOptions(Sport.table_tennis)).toEqual([PlayFormat.singles]);
    expect(getSportFormatOptions(Sport.squash)).toEqual([PlayFormat.singles]);
    expect(getSportFormatOptions(Sport.football)).toEqual([PlayFormat.doubles]);
    expect(getSportFormatOptions(Sport.volleyball)).toEqual([PlayFormat.doubles]);
  });

  it("resolves an invalid format to sport default", () => {
    expect(resolveFormatForSport(Sport.padel, PlayFormat.singles)).toBe(PlayFormat.doubles);
    expect(resolveFormatForSport(Sport.table_tennis, PlayFormat.both)).toBe(PlayFormat.singles);
    expect(resolveFormatForSport(Sport.squash, PlayFormat.doubles)).toBe(PlayFormat.singles);
    expect(resolveFormatForSport(Sport.football, PlayFormat.singles)).toBe(PlayFormat.doubles);
    expect(resolveFormatForSport(Sport.volleyball, PlayFormat.both)).toBe(PlayFormat.doubles);
  });

  it("keeps key duration defaults stable", () => {
    expect(getDefaultDurationMinutes(Sport.tennis)).toBe(90);
    expect(getDefaultDurationMinutes(Sport.padel)).toBe(90);
    expect(getDefaultDurationMinutes(Sport.squash)).toBe(60);
    expect(getDefaultDurationMinutes(Sport.table_tennis)).toBe(60);
    expect(getDefaultDurationMinutes(Sport.football)).toBe(90);
  });

  it("keeps key players-needed defaults stable", () => {
    expect(getDefaultPlayersNeeded(Sport.tennis, PlayFormat.singles)).toBe(1);
    expect(getDefaultPlayersNeeded(Sport.tennis, PlayFormat.doubles)).toBe(3);
    expect(getDefaultPlayersNeeded(Sport.padel, PlayFormat.singles)).toBe(3);
    expect(getDefaultPlayersNeeded(Sport.football, PlayFormat.singles)).toBe(9);
    expect(getDefaultPlayersNeeded(Sport.volleyball, PlayFormat.both)).toBe(5);
  });
});
