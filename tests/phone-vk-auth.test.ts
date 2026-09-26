import { createHash } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  codeFindFirst: vi.fn(),
  codeUpdate: vi.fn(),
  codeUpdateMany: vi.fn(),
  codeCreate: vi.fn(),
  userFindUnique: vi.fn(),
  userCreate: vi.fn(),
  userUpdate: vi.fn(),
  transaction: vi.fn(),
  sendSms: vi.fn(),
  attribute: vi.fn(),
  recordOnce: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    phoneAuthCode: { findFirst: mocks.codeFindFirst, update: mocks.codeUpdate, updateMany: mocks.codeUpdateMany, create: mocks.codeCreate },
    user: { findUnique: mocks.userFindUnique, create: mocks.userCreate, update: mocks.userUpdate },
    $transaction: mocks.transaction
  }
}));
vi.mock("@/lib/auth", () => ({ attributeInviteFromCookie: mocks.attribute }));
vi.mock("@/server/user-events", () => ({ recordUserEventsOnce: mocks.recordOnce }));
vi.mock("@/server/sms", async (importOriginal) => {
  const original = await importOriginal<typeof import("@/server/sms")>();
  return { ...original, sendSms: mocks.sendSms };
});

import { formatRussianPhone, normalizeRussianMobile } from "@/lib/phone";
import { phoneVerifySchema, verifySchema, vkAuthSchema } from "@/lib/validators";
import { buildLatestUserAgreementPayload } from "@/lib/legal-contract";
import { consumePhoneCode, issuePhoneCode, linkPhoneToUser, PhoneAuthError, signInWithPhone } from "@/server/phone-auth";
import { fetchVkProfile, signInWithVk } from "@/server/vk-auth";

const phone = "+79991234567";
const hash = (code: string) => createHash("sha256").update(`${phone}:${code}`).digest("hex");

beforeEach(() => {
  vi.resetAllMocks();
  mocks.transaction.mockResolvedValue([]);
  mocks.userCreate.mockImplementation(async ({ data }) => ({ id: "new-user", ...data }));
  mocks.userUpdate.mockImplementation(async ({ where, data }) => ({ id: where.id, ...data }));
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe("Russian mobile numbers", () => {
  it("accepts the usual ways of writing a Russian mobile number", () => {
    for (const input of ["+7 999 123-45-67", "89991234567", "79991234567", "(999) 123 45 67", "9991234567"]) {
      expect(normalizeRussianMobile(input)).toBe(phone);
    }
  });

  it("rejects landlines, foreign and malformed numbers — SMS only go to Russian mobiles", () => {
    for (const input of ["+7 812 123-45-67", "+380 99 123 4567", "+1 999 123 4567", "12345", ""]) {
      expect(normalizeRussianMobile(input)).toBeNull();
    }
  });

  it("formats numbers for people", () => {
    expect(formatRussianPhone(phone)).toBe("+7 999 123-45-67");
  });
});

describe("sign-in request validation", () => {
  const agreement = buildLatestUserAgreementPayload();

  it("normalizes the phone and requires a 6-digit code", () => {
    expect(phoneVerifySchema.parse({ phone: "8 999 123 45 67", code: "123456", userAgreement: agreement }).phone).toBe(phone);
    expect(phoneVerifySchema.safeParse({ phone, code: "12345", userAgreement: agreement }).success).toBe(false);
  });

  it("refuses email sign-in for someone who said they are in Russia", () => {
    const base = { email: "a@b.ru", code: "123456", userAgreement: agreement };
    expect(verifySchema.safeParse({ ...base, country: "RU" }).success).toBe(false);
    expect(verifySchema.safeParse({ ...base, country: "OTHER" }).success).toBe(true);
    // Older builds do not send the country and keep working.
    expect(verifySchema.safeParse(base).success).toBe(true);
  });

  it("requires PKCE-shaped values for VK ID", () => {
    const valid = { code: "c", codeVerifier: "a".repeat(64), deviceId: "d", state: `web_${"s".repeat(40)}`, userAgreement: agreement };
    expect(vkAuthSchema.safeParse(valid).success).toBe(true);
    expect(vkAuthSchema.safeParse({ ...valid, codeVerifier: "short" }).success).toBe(false);
  });
});

describe("SMS codes", () => {
  it("stores only a hash, cancels older codes and sends the SMS", async () => {
    const code = await issuePhoneCode(phone, { ip: "10.0.0.1" });
    expect(code).toMatch(/^\d{6}$/);
    expect(mocks.codeUpdateMany).toHaveBeenCalledWith({ where: { phone, consumedAt: null }, data: { consumedAt: expect.any(Date) } });
    const created = mocks.codeCreate.mock.calls[0][0].data;
    expect(created.codeHash).toBe(hash(code));
    expect(JSON.stringify(created)).not.toContain(code);
    expect(mocks.sendSms).toHaveBeenCalledWith(phone, expect.stringContaining(code), { ip: "10.0.0.1" });
  });

  it("accepts the right code once", async () => {
    mocks.codeFindFirst.mockResolvedValue({ id: "c1", codeHash: hash("123456"), attempts: 0 });
    mocks.codeUpdateMany.mockResolvedValue({ count: 1 });
    expect(await consumePhoneCode(phone, "123456")).toBe(true);
    mocks.codeUpdateMany.mockResolvedValue({ count: 0 });
    expect(await consumePhoneCode(phone, "123456")).toBe(false);
  });

  it("counts wrong attempts and locks the code after five", async () => {
    mocks.codeFindFirst.mockResolvedValue({ id: "c1", codeHash: hash("123456"), attempts: 2 });
    expect(await consumePhoneCode(phone, "000000")).toBe(false);
    expect(mocks.codeUpdate).toHaveBeenCalledWith({ where: { id: "c1" }, data: { attempts: { increment: 1 } } });

    mocks.codeFindFirst.mockResolvedValue({ id: "c1", codeHash: hash("123456"), attempts: 5 });
    expect(await consumePhoneCode(phone, "123456")).toBe(false);
  });
});

describe("phone sign-in and linking", () => {
  it("creates a Russian account hidden until the consent screen", async () => {
    mocks.userFindUnique.mockResolvedValue(null);
    const user = await signInWithPhone(phone, { consentReview: true });
    expect(mocks.userCreate.mock.calls[0][0].data).toMatchObject({ phone, signupCountry: "RU", profileVisibility: "pending", isVerified: true });
    expect(user.id).toBe("new-user");
    expect(mocks.recordOnce.mock.calls[0][0][0]).toMatchObject({ type: "registration_completed", context: { method: "phone" } });
  });

  it("signs an existing phone owner into the same account", async () => {
    mocks.userFindUnique.mockResolvedValue({ id: "old-user", phone });
    await signInWithPhone(phone);
    expect(mocks.userCreate).not.toHaveBeenCalled();
    expect(mocks.userUpdate.mock.calls[0][0].where).toEqual({ id: "old-user" });
  });

  it("refuses to link a number that belongs to someone else", async () => {
    mocks.userFindUnique.mockResolvedValue({ id: "someone-else" });
    await expect(linkPhoneToUser("me", phone)).rejects.toBeInstanceOf(PhoneAuthError);
    expect(mocks.userUpdate).not.toHaveBeenCalled();
  });
});

describe("VK ID", () => {
  function stubVk(user: Record<string, unknown>) {
    const fetchMock = vi.fn(async (url: string, _init?: RequestInit) => {
      const body = url.endsWith("/oauth2/auth") ? { access_token: "token", user_id: 42 } : { user };
      return new Response(JSON.stringify(body), { status: 200 });
    });
    vi.stubGlobal("fetch", fetchMock);
    return fetchMock;
  }

  it("exchanges the code with PKCE and reads a verified phone", async () => {
    vi.stubEnv("VK_ID_CLIENT_ID", "54000000");
    const fetchMock = stubVk({ user_id: 42, first_name: "Анна", last_name: "Козлова", phone: "79991234567" });
    const profile = await fetchVkProfile({ code: "code", codeVerifier: "v".repeat(64), deviceId: "device", state: "s".repeat(40) });
    expect(profile).toEqual({ userId: "42", firstName: "Анна", lastName: "Козлова", phone });
    const exchange = new URLSearchParams(fetchMock.mock.calls[0][1]?.body as URLSearchParams);
    expect(exchange.get("grant_type")).toBe("authorization_code");
    expect(exchange.get("code_verifier")).toBe("v".repeat(64));
    expect(exchange.get("device_id")).toBe("device");
    expect(exchange.get("client_id")).toBe("54000000");
    expect(exchange.get("redirect_uri")).toMatch(/\/auth\/vk\/callback$/);
  });

  it("is unavailable without a client id", async () => {
    await expect(fetchVkProfile({ code: "c", codeVerifier: "v".repeat(64), deviceId: "d", state: "s".repeat(40) })).rejects.toThrow("не настроен");
  });

  it("joins the account that already owns the VK-verified phone", async () => {
    mocks.userFindUnique.mockImplementation(async ({ where }) => (where.phone ? { id: "phone-owner", phone, vkSubject: null } : null));
    await signInWithVk({ userId: "42", firstName: "Анна", lastName: "Козлова", phone });
    expect(mocks.userCreate).not.toHaveBeenCalled();
    expect(mocks.userUpdate.mock.calls[0][0]).toMatchObject({ where: { id: "phone-owner" }, data: { vkSubject: "42" } });
  });

  it("creates an account with only the first name — the surname is never shown publicly", async () => {
    mocks.userFindUnique.mockResolvedValue(null);
    await signInWithVk({ userId: "42", firstName: "Анна", lastName: "Козлова", phone: null }, { consentReview: true });
    expect(mocks.userCreate.mock.calls[0][0].data).toMatchObject({ vkSubject: "42", name: "Анна", phone: null, signupCountry: "RU" });
  });
});

describe("VK ID return route", () => {
  const state = (prefix: string) => `${prefix}_${"s".repeat(40)}`;

  it("hands the code back to the app that started the sign-in", async () => {
    const { GET } = await import("@/app/auth/vk/callback/route");
    const { NextRequest } = await import("next/server");
    const app = GET(new NextRequest(`https://sportsearch.shop/auth/vk/callback?code=abc&device_id=dev&state=${state("ios")}`));
    expect(app.status).toBe(302);
    expect(app.headers.get("location")).toBe(`sportsearch://auth/vk?code=abc&device_id=dev&state=${state("ios")}`);

    const web = GET(new NextRequest(`https://sportsearch.shop/auth/vk/callback?code=abc&device_id=dev&state=${state("web")}`));
    expect(web.headers.get("location")).toBe(`https://sportsearch.shop/auth/vk/finish?code=abc&device_id=dev&state=${state("web")}`);
  });
});
