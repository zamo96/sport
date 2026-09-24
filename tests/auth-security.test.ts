import { generateKeyPairSync, sign } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  findUser: vi.fn(), createUser: vi.fn(), updateUser: vi.fn(), linkUser: vi.fn(),
  findCode: vi.fn(), consumeCode: vi.fn(), cookieGet: vi.fn(), cookieDelete: vi.fn(), headerGet: vi.fn(),
  queryRaw: vi.fn(), findSession: vi.fn(), deleteSessions: vi.fn(), updateDevices: vi.fn(), transaction: vi.fn()
}));
vi.mock("@/lib/prisma", () => ({ prisma: {
  user: { findUnique: mocks.findUser, create: mocks.createUser, update: mocks.updateUser, updateMany: mocks.linkUser },
  authCode: { findFirst: mocks.findCode, updateMany: mocks.consumeCode },
  session: { findUnique: mocks.findSession }, $transaction: mocks.transaction
} }));
vi.mock("next/headers", () => ({
  cookies: () => ({ get: mocks.cookieGet, delete: mocks.cookieDelete }),
  headers: () => ({ get: mocks.headerGet })
}));
vi.mock("@/server/user-events", () => ({ recordUserEventsOnce: vi.fn() }));
vi.mock("@/lib/invites", () => ({ attributeInvite: vi.fn(), INVITE_COOKIE_NAME: "invite" }));

import { destroySession, getSessionUser, signInWithAppleIdentityToken, verifyAuthCode } from "@/lib/auth";

const keys = generateKeyPairSync("rsa", { modulusLength: 2048 });
const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
function appleToken(claims: Record<string, unknown> = {}) {
  const input = `${encode({ alg: "RS256", kid: "security-test" })}.${encode({
    iss: "https://appleid.apple.com", aud: "shop.sportsearch.app", sub: "apple-player",
    exp: Math.floor(Date.now() / 1000) + 3600, ...claims
  })}`;
  return `${input}.${sign("RSA-SHA256", Buffer.from(input), keys.privateKey).toString("base64url")}`;
}

beforeEach(() => {
  vi.resetAllMocks();
  vi.stubEnv("APPLE_CLIENT_IDS", "shop.sportsearch.app");
  mocks.findUser.mockResolvedValue(null);
  mocks.linkUser.mockResolvedValue({ count: 1 });
  mocks.createUser.mockImplementation(async ({ data }) => ({ id: "new", ...data }));
  mocks.transaction.mockImplementation(async (callback) => callback({
    $queryRaw: mocks.queryRaw, session: { deleteMany: mocks.deleteSessions },
    pushDevice: { updateMany: mocks.updateDevices }
  }));
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ keys: [
    { ...keys.publicKey.export({ format: "jwk" }), kid: "security-test" }
  ] }) }));
});
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

describe("Apple identity binding", () => {
  it("cannot use an unsigned profile email to sign into an existing email account", async () => {
    await expect(signInWithAppleIdentityToken(appleToken(), { email: "victim@example.com" })).rejects.toThrow("email");
    expect(mocks.findUser).toHaveBeenCalledExactlyOnceWith({ where: { appleSubject: "apple-player" } });
    expect(mocks.createUser).not.toHaveBeenCalled();
  });
  it.each([undefined, false, "false"])("rejects unverified token email (%s)", async (verified) => {
    await expect(signInWithAppleIdentityToken(appleToken({ email: "victim@example.com", email_verified: verified }))).rejects.toThrow("email");
    expect(mocks.findUser).toHaveBeenCalledTimes(1);
  });
  it.each([true, "true"])("creates an account using verified signed email (%s)", async (verified) => {
    const user = await signInWithAppleIdentityToken(appleToken({ email: "owner@example.com", email_verified: verified }), { email: "victim@example.com" });
    expect(user.email).toBe("owner@example.com");
  });
  it("allows repeat subject login without requiring email again", async () => {
    const user = { id: "existing", appleSubject: "apple-player", isVerified: true };
    mocks.findUser.mockResolvedValue(user);
    await expect(signInWithAppleIdentityToken(appleToken())).resolves.toEqual(user);
  });
  it("rejects verified email pointing at a different Apple subject", async () => {
    mocks.findUser.mockResolvedValueOnce(null).mockResolvedValueOnce({ id: "victim", appleSubject: "different" });
    await expect(signInWithAppleIdentityToken(appleToken({ email: "owner@example.com", email_verified: true }))).rejects.toThrow("привязанному");
    expect(mocks.linkUser).not.toHaveBeenCalled();
  });
  it("does not overwrite a concurrently bound Apple subject", async () => {
    mocks.findUser.mockResolvedValueOnce(null).mockResolvedValueOnce({ id: "existing", appleSubject: null });
    mocks.linkUser.mockResolvedValue({ count: 0 });
    await expect(signInWithAppleIdentityToken(appleToken({ email: "owner@example.com", email_verified: true }))).rejects.toThrow("привязанному");
    expect(mocks.linkUser).toHaveBeenCalledWith({ where: { id: "existing", appleSubject: null }, data: { appleSubject: "apple-player" } });
    expect(mocks.updateUser).not.toHaveBeenCalled();
  });
});

describe("OTP one-time use", () => {
  it("rejects a code consumed by a concurrent verification", async () => {
    mocks.findCode.mockResolvedValue({ id: "code", userId: "player" });
    mocks.consumeCode.mockResolvedValue({ count: 0 });
    await expect(verifyAuthCode("owner@example.com", "123456")).resolves.toBeNull();
    expect(mocks.consumeCode).toHaveBeenCalledWith({ where: { id: "code", consumedAt: null, expiresAt: { gt: expect.any(Date) } }, data: { consumedAt: expect.any(Date) } });
    expect(mocks.findUser).not.toHaveBeenCalled();
  });
});

describe("native sessions", () => {
  it("uses the explicit bearer identity even when a stale cookie exists", async () => {
    mocks.cookieGet.mockReturnValue({ value: "stale-cookie" });
    mocks.headerGet.mockReturnValue("Bearer native-token");
    mocks.findSession.mockResolvedValue(null);
    await getSessionUser();
    expect(mocks.findSession).toHaveBeenCalledWith({ where: { token: "native-token" }, include: { user: true } });
  });
  it("revokes bearer session and only its owner's APNs device on logout", async () => {
    mocks.cookieGet.mockReturnValue({ value: "stale-cookie" });
    mocks.headerGet.mockReturnValue("Bearer native-token");
    mocks.queryRaw.mockResolvedValue([{ userId: "owner" }]);
    await destroySession("device-token");
    expect(mocks.deleteSessions).toHaveBeenCalledWith({ where: { token: "native-token" } });
    expect(mocks.updateDevices).toHaveBeenCalledWith({ where: { token: "device-token", userId: "owner", platform: "ios" }, data: { isActive: false } });
    expect(mocks.cookieDelete).toHaveBeenCalled();
  });
  it("keeps other devices active for ordinary browser logout", async () => {
    mocks.cookieGet.mockReturnValue({ value: "cookie" });
    mocks.queryRaw.mockResolvedValue([{ userId: "owner" }]);
    await destroySession();
    expect(mocks.deleteSessions).toHaveBeenCalledWith({ where: { token: "cookie" } });
    expect(mocks.updateDevices).not.toHaveBeenCalled();
  });
  it("does not deactivate a device without a matching session", async () => {
    mocks.headerGet.mockReturnValue("Bearer expired-or-revoked");
    mocks.queryRaw.mockResolvedValue([]);
    await destroySession("device-token");
    expect(mocks.updateDevices).not.toHaveBeenCalled();
  });
});
