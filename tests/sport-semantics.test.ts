import { describe, expect, it } from "vitest";

import { PlayFormat, Sport } from "@prisma/client";

import { getSportPlayFormatLabelRu, getSportVenueShortLabelRu } from "@/lib/sport-semantics";

describe("sport semantics (sport-aware labels)", () => {
  it("does not call team sports 'Парная' for doubles", () => {
    expect(getSportPlayFormatLabelRu(Sport.football, PlayFormat.doubles)).toBe("Командная");
    expect(getSportPlayFormatLabelRu(Sport.volleyball, PlayFormat.doubles)).toBe("Командная");
  });

  it("keeps tennis doubles as 'Парная'", () => {
    expect(getSportPlayFormatLabelRu(Sport.tennis, PlayFormat.doubles)).toBe("Парная");
  });

  it("labels 1v1 for team sports singles", () => {
    expect(getSportPlayFormatLabelRu(Sport.football, PlayFormat.singles)).toBe("Один на один");
    expect(getSportPlayFormatLabelRu(Sport.volleyball, PlayFormat.singles)).toBe("Один на один");
  });

  it("does not label yoga venue as 'Корт'", () => {
    expect(getSportVenueShortLabelRu(Sport.yoga)).toBe("Студия");
    expect(getSportVenueShortLabelRu(Sport.yoga)).not.toContain("корт");
    expect(getSportVenueShortLabelRu(Sport.yoga)).not.toBe("Корт");
  });
});
