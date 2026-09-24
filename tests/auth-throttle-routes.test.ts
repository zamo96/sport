import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks = vi.hoisted(() => ({ limit: vi.fn(), verify: vi.fn(), createCode: vi.fn(), send: vi.fn(), demo: vi.fn() }));
vi.mock("@/server/auth-rate-limit", () => ({ enforceAuthRateLimit: mocks.limit }));
vi.mock("@/lib/auth", () => ({ verifyAuthCode: mocks.verify, createAuthCode: mocks.createCode, isAppReviewDemoEmail: mocks.demo, createSession: vi.fn(), recordUserAgreementAcceptance: vi.fn(), getLegalAcceptanceRequestMeta: vi.fn() }));
vi.mock("@/lib/email", () => ({ sendOtpEmail: mocks.send }));
vi.mock("@/lib/prisma", () => ({ prisma: { user: { findUnique: vi.fn() } } }));
import { POST as requestPost } from "@/app/auth/request-link/route";
import { POST as verifyPost } from "@/app/auth/verify/route";
import { USER_AGREEMENT_VERSION } from "@/lib/legal-contract";
const request = () => new NextRequest("https://example.com/auth", { method: "POST", headers: { "x-app-locale": "en" }, body: JSON.stringify({ email: "owner@example.com", code: "123456", userAgreement: { accepted: true, version: USER_AGREEMENT_VERSION } }) });
beforeEach(() => vi.resetAllMocks());
afterEach(() => vi.unstubAllEnvs());
describe("login endpoint limits", () => {
  it.each([requestPost, verifyPost])("returns 429 and does not issue or verify credentials after throttling", async (post) => {
    mocks.limit.mockRejectedValue(new Error("AUTH_RATE_LIMITED"));
    const response = await post(request());
    expect(response.status).toBe(429);
    expect((await response.json()).errorCode).toBe("AUTH_RATE_LIMITED");
    expect(mocks.verify).not.toHaveBeenCalled();
    expect(mocks.createCode).not.toHaveBeenCalled();
    expect(mocks.send).not.toHaveBeenCalled();
    expect(mocks.demo).not.toHaveBeenCalled();
  });
  it.each([requestPost, verifyPost])("returns 503 if the shared limiter is unavailable", async (post) => {
    mocks.limit.mockRejectedValue(new Error("AUTH_RATE_LIMIT_UNAVAILABLE"));
    const response = await post(request());
    expect(response.status).toBe(503);
    expect((await response.json()).errorCode).toBe("AUTH_UNAVAILABLE");
    expect(mocks.verify).not.toHaveBeenCalled();
    expect(mocks.createCode).not.toHaveBeenCalled();
  });
});
