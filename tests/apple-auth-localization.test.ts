import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  appleSignIn: vi.fn(),
  recordAcceptance: vi.fn(),
  createSession: vi.fn(),
  updateUser: vi.fn()
}));

vi.mock("@/lib/auth", () => ({
  signInWithAppleIdentityToken: mocks.appleSignIn,
  recordUserAgreementAcceptance: mocks.recordAcceptance,
  createSession: mocks.createSession,
  getLegalAcceptanceRequestMeta: () => ({ ip: "127.0.0.1", userAgent: "test" })
}));
vi.mock("@/lib/prisma", () => ({ prisma: { user: { update: mocks.updateUser } } }));

import { POST as applePost } from "@/app/auth/apple/route";
import { USER_AGREEMENT_VERSION } from "@/lib/legal-contract";

const requestBody = {
  identityToken: "apple-token",
  userAgreement: { accepted: true, version: USER_AGREEMENT_VERSION }
};

function appleRequest(headers: Record<string, string>) {
  return new NextRequest("https://example.com/auth/apple", {
    method: "POST",
    headers,
    body: JSON.stringify(requestBody)
  });
}

describe("Apple auth localization", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
  });

  it("returns a safe English error without leaking token verification details", async () => {
    mocks.appleSignIn.mockRejectedValue(new Error("Apple identity token не прошёл проверку подписи"));

    const response = await applePost(appleRequest({ "x-app-locale": "en" }));
    const payload = await response.json();

    expect(response.status).toBe(401);
    expect(payload).toEqual({
      error: "Apple sign-in could not be verified. Start the Apple sign-in flow again.",
      errorCode: "AUTH_APPLE_INVALID_TOKEN"
    });
    expect(payload.error).not.toContain("подписи");
  });

  it("returns the same safe category in Russian", async () => {
    mocks.appleSignIn.mockRejectedValue(new Error("Apple identity token выпущен неизвестным issuer"));

    const response = await applePost(appleRequest({ "x-app-locale": "ru" }));

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: "Не удалось подтвердить вход через Apple. Запустите вход через Apple ещё раз.",
      errorCode: "AUTH_APPLE_INVALID_TOKEN"
    });
  });

  it("separates a provider outage from invalid credentials", async () => {
    mocks.appleSignIn.mockRejectedValue(new Error("Не удалось получить ключи Apple для входа"));

    const response = await applePost(appleRequest({ "accept-language": "en-US" }));

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: "Apple sign-in is temporarily unavailable. Please try again later.",
      errorCode: "AUTH_APPLE_UNAVAILABLE"
    });
  });
});
