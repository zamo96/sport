import { describe, expect, it } from "vitest";

import {
  buildInviteUrl,
  generateInviteCode,
  INVITE_CODE_LENGTH,
  normalizeInviteCode
} from "@/lib/invites";

describe("invite codes", () => {
  it("generates codes without lookalike characters", () => {
    for (let attempt = 0; attempt < 200; attempt += 1) {
      const code = generateInviteCode();
      expect(code).toHaveLength(INVITE_CODE_LENGTH);
      // I/O/0/1 путают при диктовке и переписывании от руки.
      expect(code).not.toMatch(/[IO01]/);
      expect(normalizeInviteCode(code)).toBe(code);
    }
  });

  it("accepts what a person would actually type", () => {
    expect(normalizeInviteCode("k7m2qp")).toBe("K7M2QP");
    expect(normalizeInviteCode("  K7M2QP  ")).toBe("K7M2QP");
  });

  it("rejects anything that is not a code", () => {
    expect(normalizeInviteCode("K7M2Q")).toBeNull();
    expect(normalizeInviteCode("K7M2QPX")).toBeNull();
    expect(normalizeInviteCode("K7M2Q0")).toBeNull();
    expect(normalizeInviteCode("K7M2QI")).toBeNull();
    expect(normalizeInviteCode("K7M-QP")).toBeNull();
    expect(normalizeInviteCode(null)).toBeNull();
    expect(normalizeInviteCode(123456)).toBeNull();
  });
});

describe("invite url", () => {
  it("builds a link people can retype", () => {
    expect(buildInviteUrl("K7M2QP", "https://sportsearch.shop")).toBe("https://sportsearch.shop/i/K7M2QP");
  });

  it("tolerates a trailing slash in the origin", () => {
    expect(buildInviteUrl("K7M2QP", "https://sportsearch.shop/")).toBe("https://sportsearch.shop/i/K7M2QP");
  });
});
