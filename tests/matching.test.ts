import { describe, expect, it } from "vitest";
import { GameRequestStatus } from "@prisma/client";

import { canTransitionGameRequest, normalizeMatchPair } from "@/server/matching";

describe("matching helpers", () => {
  it("normalizes match pair ordering", () => {
    expect(normalizeMatchPair("user-b", "user-a")).toEqual(["user-a", "user-b"]);
  });

  it("allows only valid game request transitions", () => {
    expect(canTransitionGameRequest(GameRequestStatus.pending, GameRequestStatus.accepted)).toBe(true);
    expect(canTransitionGameRequest(GameRequestStatus.accepted, GameRequestStatus.declined)).toBe(false);
  });
});

