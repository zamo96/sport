import { generateKeyPairSync, createSign, type KeyObject } from "crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  findUnique: vi.fn(),
  create: vi.fn(),
  updateMany: vi.fn(),
  update: vi.fn(),
  events: vi.fn(),
  invite: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    user: { findUnique: mocks.findUnique, create: mocks.create, updateMany: mocks.updateMany, update: mocks.update }
  }
}));
vi.mock("@/server/user-events", () => ({ recordUserEventsOnce: mocks.events }));
vi.mock("@/lib/invites", () => ({ attributeInvite: mocks.invite, INVITE_COOKIE_NAME: "invite" }));
vi.mock("next/headers", () => ({ cookies: () => ({ get: () => undefined }) }));

import {
  resetGoogleJwksCache,
  resolveLocalizedGoogleAuthError,
  signInWithGoogleIdToken,
  verifyGoogleIdToken
} from "@/lib/google-auth";

const CLIENT_ID = "1234-web.apps.googleusercontent.com";
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const KID = "test-key";

function toBase64URL(input: Buffer | string) {
  return (Buffer.isBuffer(input) ? input : Buffer.from(input))
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function signToken(claims: Record<string, unknown>, options: { key?: KeyObject; kid?: string } = {}) {
  const header = toBase64URL(JSON.stringify({ alg: "RS256", kid: options.kid ?? KID, typ: "JWT" }));
  const payload = toBase64URL(JSON.stringify(claims));
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${payload}`);
  signer.end();
  return `${header}.${payload}.${toBase64URL(signer.sign(options.key ?? privateKey))}`;
}

function validClaims(overrides: Record<string, unknown> = {}) {
  return {
    iss: "https://accounts.google.com",
    aud: CLIENT_ID,
    sub: "google-sub-1",
    email: "Player@Example.com",
    email_verified: true,
    name: "Иван Петров",
    exp: Math.floor(Date.now() / 1000) + 600,
    ...overrides
  };
}

beforeEach(() => {
  vi.resetAllMocks();
  resetGoogleJwksCache();
  process.env.GOOGLE_CLIENT_IDS = CLIENT_ID;
  const jwk = { ...publicKey.export({ format: "jwk" }), kid: KID, alg: "RS256", use: "sig" };
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: true, json: async () => ({ keys: [jwk] }) }) as unknown as Response)
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.GOOGLE_CLIENT_IDS;
});

describe("Google ID token verification", () => {
  it("accepts a token signed by Google for this app", async () => {
    const payload = await verifyGoogleIdToken(signToken(validClaims()));
    expect(payload.sub).toBe("google-sub-1");
  });

  it("rejects a token issued for another app", async () => {
    await expect(verifyGoogleIdToken(signToken(validClaims({ aud: "someone-else" })))).rejects.toThrow(
      "выпущен не для этого приложения"
    );
  });

  it("rejects a token from an unknown issuer", async () => {
    await expect(verifyGoogleIdToken(signToken(validClaims({ iss: "https://evil.example" })))).rejects.toThrow(
      "неизвестным issuer"
    );
  });

  it("rejects an expired token", async () => {
    const expired = validClaims({ exp: Math.floor(Date.now() / 1000) - 5 });
    await expect(verifyGoogleIdToken(signToken(expired))).rejects.toThrow("просрочен");
  });

  it("rejects a token signed with a different key", async () => {
    const { privateKey: otherKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
    await expect(verifyGoogleIdToken(signToken(validClaims(), { key: otherKey }))).rejects.toThrow(
      "не прошёл проверку подписи"
    );
  });

  it("refuses to run without a configured client ID", async () => {
    delete process.env.GOOGLE_CLIENT_IDS;
    await expect(verifyGoogleIdToken(signToken(validClaims()))).rejects.toThrow("не настроен");
  });
});

describe("Google account linking", () => {
  it("creates a verified account for a new player", async () => {
    mocks.findUnique.mockResolvedValue(null);
    mocks.create.mockImplementation(async ({ data }) => ({ id: "new-user", ...data }));

    const user = await signInWithGoogleIdToken(signToken(validClaims()), { showOnMap: false });

    expect(mocks.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        email: "player@example.com",
        googleSubject: "google-sub-1",
        name: "Иван Петров",
        isVerified: true,
        showOnMap: false
      })
    });
    expect(user.id).toBe("new-user");
    expect(mocks.events).toHaveBeenCalledWith([
      expect.objectContaining({ type: "registration_completed", context: { method: "google" } })
    ]);
  });

  it("links Google to an existing account with the same verified email", async () => {
    const existing = { id: "user-1", email: "player@example.com", googleSubject: null, isVerified: true, name: "Иван" };
    mocks.findUnique.mockImplementation(async ({ where }) => (where.email ? existing : null));
    mocks.updateMany.mockResolvedValue({ count: 1 });

    const user = await signInWithGoogleIdToken(signToken(validClaims()));

    expect(mocks.updateMany).toHaveBeenCalledWith({
      where: { id: "user-1", googleSubject: null },
      data: { googleSubject: "google-sub-1" }
    });
    expect(user.id).toBe("user-1");
    expect(mocks.create).not.toHaveBeenCalled();
  });

  it("never matches an existing account by an unverified email", async () => {
    mocks.findUnique.mockImplementation(async ({ where }) =>
      where.email ? { id: "victim", email: "player@example.com" } : null
    );

    await expect(
      signInWithGoogleIdToken(signToken(validClaims({ email_verified: false })))
    ).rejects.toThrow("не передал подтверждённый email");
    expect(mocks.updateMany).not.toHaveBeenCalled();
  });

  it("refuses an account already bound to a different Google identity", async () => {
    mocks.findUnique.mockImplementation(async ({ where }) =>
      where.email ? { id: "user-1", email: "player@example.com", googleSubject: "another-sub" } : null
    );

    await expect(signInWithGoogleIdToken(signToken(validClaims()))).rejects.toThrow(
      "не соответствует привязанному аккаунту"
    );
  });
});

describe("Google sign-in errors", () => {
  it("reports an invalid token as 401 with a localized message", () => {
    const result = resolveLocalizedGoogleAuthError(new Error("Google ID token просрочен"), "ru", "google");
    expect(result.status).toBe(401);
    expect(result.errorCode).toBe("AUTH_GOOGLE_INVALID_TOKEN");
    expect(result.message).toContain("Google");
  });

  it("reports a missing server configuration as unavailable, not as the user's fault", () => {
    const result = resolveLocalizedGoogleAuthError(new Error("Вход через Google не настроен на сервере"), "en", "google");
    expect(result.status).toBe(503);
    expect(result.errorCode).toBe("AUTH_GOOGLE_UNAVAILABLE");
  });
});
