import { generateKeyPairSync, sign } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ find: vi.fn(), create: vi.fn(), update: vi.fn(), code: vi.fn() }));
vi.mock("@/lib/prisma", () => ({ prisma: {
  user: { findUnique: mocks.find, create: mocks.create, update: mocks.update },
  authCode: { findFirst: mocks.code, update: vi.fn() }
} }));
vi.mock("next/headers", () => ({ cookies: () => ({ get: () => undefined }), headers: () => ({ get: () => null }) }));
vi.mock("@/server/user-events", () => ({ recordUserEventsOnce: vi.fn() }));
vi.mock("@/lib/invites", () => ({ attributeInvite: vi.fn(), INVITE_COOKIE_NAME: "invite" }));

import { signInWithAppleIdentityToken, verifyAuthCode } from "@/lib/auth";

const keys = generateKeyPairSync("rsa", { modulusLength: 2048 });
const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
function appleToken() {
  const input = `${encode({ alg: "RS256", kid: "map-test" })}.${encode({
    iss: "https://appleid.apple.com", aud: "shop.sportsearch.app", sub: "apple-player",
    exp: Math.floor(Date.now() / 1000) + 3600, email: "map-player@example.com"
  })}`;
  return `${input}.${sign("RSA-SHA256", Buffer.from(input), keys.privateKey).toString("base64url")}`;
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("APPLE_CLIENT_IDS", "shop.sportsearch.app");
  mocks.code.mockResolvedValue({ id: "code", userId: null });
  mocks.find.mockResolvedValue(null);
  mocks.create.mockImplementation(async ({ data }) => ({ id: "new", ...data }));
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ keys: [
    { ...keys.publicKey.export({ format: "jwk" }), kid: "map-test" }
  ] }) }));
});
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

describe("new-account map default and saved login preference", () => {
  it.each(["email", "apple"])("%s creation defaults on and accepts an explicit off", async (method) => {
    for (const choice of [undefined, false]) {
      const user = method === "email"
        ? await verifyAuthCode("map-player@example.com", "123456", choice)
        : await signInWithAppleIdentityToken(appleToken(), { showOnMap: choice });
      expect(user?.showOnMap).toBe(choice ?? true);
      expect(mocks.create.mock.lastCall?.[0].data.showOnMap).toBe(choice ?? true);
    }
  });
  it.each(["email", "apple"])("%s repeat login ignores a new true choice and keeps saved false", async (method) => {
    const saved = { id: "existing", email: "map-player@example.com", appleSubject: "apple-player", isVerified: true, showOnMap: false };
    mocks.find.mockResolvedValue(saved);
    const user = method === "email"
      ? await verifyAuthCode(saved.email, "123456", true)
      : await signInWithAppleIdentityToken(appleToken(), { showOnMap: true });
    expect(user?.showOnMap).toBe(false);
    expect(mocks.create).not.toHaveBeenCalled();
    expect(mocks.update).not.toHaveBeenCalled();
  });
});
