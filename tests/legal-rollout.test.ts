import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  verifyAuthCode: vi.fn(),
  appleSignIn: vi.fn(),
  recordAcceptance: vi.fn(),
  createSession: vi.fn(),
  updateUser: vi.fn()
}));

vi.mock("@/lib/auth", () => ({
  verifyAuthCode: mocks.verifyAuthCode,
  signInWithAppleIdentityToken: mocks.appleSignIn,
  recordUserAgreementAcceptance: mocks.recordAcceptance,
  createSession: mocks.createSession,
  getLegalAcceptanceRequestMeta: () => ({ ip: "127.0.0.1", userAgent: "test" })
}));
vi.mock("@/server/auth-rate-limit", () => ({ enforceAuthRateLimit: vi.fn() }));
vi.mock("@/lib/prisma", () => ({ prisma: { user: { update: mocks.updateUser } } }));

import { POST as verifyPost } from "@/app/auth/verify/route";
import { POST as applePost } from "@/app/auth/apple/route";
import { LEGACY_USER_AGREEMENT_VERSION } from "@/lib/legal-contract";

const user = { id: "user-1", email: "player@example.com", onboardingCompleted: true };

describe("legacy agreement rollout", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.verifyAuthCode.mockResolvedValue(user);
    mocks.appleSignIn.mockResolvedValue(user);
    mocks.recordAcceptance.mockResolvedValue(user);
    mocks.createSession.mockResolvedValue("session-token");
    mocks.updateUser.mockResolvedValue(user);
  });

  it("passes the submitted legacy version through email verification", async () => {
    const response = await verifyPost(new NextRequest("https://example.com/auth/verify", {
      method: "POST",
      body: JSON.stringify({
        email: user.email,
        code: "123456",
        userAgreement: { accepted: true, version: LEGACY_USER_AGREEMENT_VERSION }
      })
    }));
    expect(response.status).toBe(200);
    expect(mocks.recordAcceptance).toHaveBeenCalledWith(
      user.id,
      "email_otp",
      LEGACY_USER_AGREEMENT_VERSION,
      { ip: "127.0.0.1", userAgent: "test" }
    );
  });

  it("passes the submitted legacy version through Apple sign-in", async () => {
    const response = await applePost(new NextRequest("https://example.com/auth/apple", {
      method: "POST",
      body: JSON.stringify({
        identityToken: "apple-token",
        userAgreement: { accepted: true, version: LEGACY_USER_AGREEMENT_VERSION }
      })
    }));
    expect(response.status).toBe(200);
    expect(mocks.recordAcceptance).toHaveBeenCalledWith(
      user.id,
      "apple",
      LEGACY_USER_AGREEMENT_VERSION,
      { ip: "127.0.0.1", userAgent: "test" }
    );
  });
});
