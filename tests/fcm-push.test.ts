import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  findMany: vi.fn(),
  update: vi.fn(),
  findFirst: vi.fn(),
  realtime: vi.fn(),
  apns: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    pushDevice: { findMany: mocks.findMany, update: mocks.update },
    user: { findFirst: mocks.findFirst }
  }
}));
vi.mock("@/server/realtime", () => ({ publishRealtimeEvent: mocks.realtime }));
vi.mock("@/lib/apns", () => ({ deliverAPNSPush: mocks.apns }));

import { deliverFCMPush, resetFCMAccessTokenCache } from "@/lib/fcm";
import { sendPushToUser } from "@/lib/push";

const payload = {
  userId: "user-1",
  title: "Кто-то хочет сыграть",
  body: "Откройте приложение",
  href: "/discover?tab=likes"
};

// A throwaway key so the assertion can actually be signed in the test.
const PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDDCX4zSmcX6/hx
uOPE6k0qRw5Y8xXmAAlCZk33xofkgiccw+jysbPlQidavLOhfB88Xrxh/zQg/Dwv
+ruvF0OXr3oDdo4yAJdLecCoQLgoLAn0IhTDD0GT4dUkv7rwPfrMY9TUPjLs6FH3
A6ltWTjzHpf8wUZyta+00D7i7AvDEe4+UMEPSvpcHLOkqCSZchf7NNHzl8BAopit
Hg0OAOPPDG08bKgVN7SLmnpCsRAoAP6oS8vbVp0+ZO+tHAbK0j0qZp02anNyUvaE
bbHsH+r42NlQSIXh/3X23DAzRfmB16PxLAaYIGSeq2t/pDUbMVBfkoP3jhmAyIy9
IZ1l+ZAtAgMBAAECggEAF1oP3ubB5LKXXtBfDxDpl84FqP9D6DOpaCaVH71IwIKX
2cEYJ1TBAApVaW8OB9/zYnhKUGZssKVatHjuF1bu/B6hun/row+AjeQgPdTv57ls
IKui9j7hoGnp6fo90O1u1aF/VkEzOjvPsoZg9wt3ft5zHqtqeqoHxVuop+VQvDR3
veW2NHvXRdcnkH0VE89BgvWx7Emo/RxDkyqvk3XnVC+llxuCpNiTX77oyG+Vl9oQ
8UWx0zWaUwBrWdrMoyFbTLstdHgRpXER+jX54+b/3/NBtBWDhDZp/R8oNw/N85F1
Xezlyy1LiyqA4N+ZwTaf+qaVBEC6F9ivukFCxBtHGQKBgQD8QX3OQgJ7xjYWY5kQ
3s/vNALRdJE1Y51+K9Sc0Tl1H1CeIrJ9LIXBor7yDQKVqms5kiRAxBbWFO51H888
V79iaS6NO+HIh0uQCQupyqFNfuE058WkK/VcGA8TJhQYjw/WvxoLkLs6/hQmAGGd
94vsaCcZDYg5nii7LJt3bFxbSQKBgQDF7pWxFKYYZfHKmzir+AXThaMI9Gx+nsNk
C0HtQGSV6CrfJt8uO7XZOSeYpDP2bUBEOzhZpISCcTSQlMhRQAHy6zlxYkW3qntD
LC3eibf6JCKJ/tDJbkRMJOyBCCMoAGVsTZ8eAjJd0gQl0GpZD1t0vjfGZmO5rdP1
hOjvomPJxQKBgBDe1GoZ8g6TGATxTkhZjnCB+vpFIH0Al4Tbq5F9UKlrmbmpumQy
uRNVLg4EHrshtaAZDQGj258fsT72DKcNe0g6nplletktazlL0ZLecWE8bhVattYe
9n7dQQzXzBpEXxvOlhBV8p+kZHaSKfUlnB8IbCz5wbWQxUqXViJrhdW5AoGBALn+
SIvua2Xh5iQNWGPA3Ti3C00O4iTZ66HHMlxPdjWnxSGM1YwMcAV/v8WgB3Q5lXqI
a5tRDXPGDS8PoG05SJuMjp4NSpYcjVfB3BiSMV/NNOeXm3qtM2CaEePuUZr1RFlR
V4RLbCjdgShHgKfP1pENbjvxWyTQQ60jCACnCD5BAoGAZ5hiv887k5EZjZQ9/vSs
ltu9QbYGs5FRaKsMcLmeYKvbGhitospw2281z9OEddQsjEFa9o2dwzRgyCnxDnO4
Di17bqQamPCWSV2RA4uLzj8kL2h5AEUosSl+NXszXk0Pzq1tKJ6ihXEAFeTSCoY4
DFLJK+n/idwFntKxgXzK/GI=
-----END PRIVATE KEY-----`;

function configureFCM() {
  process.env.FCM_PROJECT_ID = "sportsearch-test";
  process.env.FCM_CLIENT_EMAIL = "push@sportsearch-test.iam.gserviceaccount.com";
  process.env.FCM_PRIVATE_KEY = PRIVATE_KEY;
}

function stubFetch(send: { status: number; body: string }) {
  const calls: { url: string; init: RequestInit }[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init: RequestInit) => {
      calls.push({ url: String(url), init });
      if (String(url).includes("oauth2.googleapis.com")) {
        return {
          ok: true,
          status: 200,
          json: async () => ({ access_token: "access-token", expires_in: 3600 })
        } as unknown as Response;
      }
      return {
        status: send.status,
        text: async () => send.body
      } as unknown as Response;
    })
  );
  return calls;
}

beforeEach(() => {
  vi.resetAllMocks();
  resetFCMAccessTokenCache();
  delete process.env.FCM_PROJECT_ID;
  delete process.env.FCM_CLIENT_EMAIL;
  delete process.env.FCM_PRIVATE_KEY;
  mocks.update.mockResolvedValue({});
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("FCM delivery", () => {
  it("does nothing when the user has no android devices", async () => {
    configureFCM();
    mocks.findMany.mockResolvedValue([]);
    const calls = stubFetch({ status: 200, body: "{}" });

    await deliverFCMPush(payload);

    expect(calls).toHaveLength(0);
    expect(mocks.update).not.toHaveBeenCalled();
  });

  it("skips delivery without credentials instead of throwing", async () => {
    mocks.findMany.mockResolvedValue([{ id: "device-1", token: "token-1" }]);
    const calls = stubFetch({ status: 200, body: "{}" });

    await expect(deliverFCMPush(payload)).resolves.toBeUndefined();

    expect(calls).toHaveLength(0);
    expect(mocks.update).not.toHaveBeenCalled();
  });

  it("sends the notification and the href the app routes on", async () => {
    configureFCM();
    mocks.findMany.mockResolvedValue([{ id: "device-1", token: "token-1" }]);
    const calls = stubFetch({ status: 200, body: JSON.stringify({ name: "projects/x/messages/1" }) });

    await deliverFCMPush(payload);

    const send = calls.find((call) => call.url.includes("fcm.googleapis.com"));
    expect(send?.url).toContain("/v1/projects/sportsearch-test/messages:send");

    const message = JSON.parse(String(send?.init.body)).message;
    expect(message.token).toBe("token-1");
    expect(message.notification).toEqual({ title: payload.title, body: payload.body });
    expect(message.data.href).toBe(payload.href);
    expect(message.android.priority).toBe("high");

    expect(mocks.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "device-1" },
        data: expect.objectContaining({ lastFailureReason: null })
      })
    );
  });

  it("retires a token Google reports as unregistered", async () => {
    configureFCM();
    mocks.findMany.mockResolvedValue([{ id: "device-1", token: "token-1" }]);
    stubFetch({
      status: 404,
      body: JSON.stringify({
        error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] }
      })
    });

    await deliverFCMPush(payload);

    expect(mocks.update).toHaveBeenCalledWith({
      where: { id: "device-1" },
      data: expect.objectContaining({ isActive: false, lastFailureReason: "UNREGISTERED" })
    });
  });

  it("keeps the device active when FCM is merely unavailable", async () => {
    configureFCM();
    mocks.findMany.mockResolvedValue([{ id: "device-1", token: "token-1" }]);
    stubFetch({ status: 503, body: JSON.stringify({ error: { status: "UNAVAILABLE" } }) });

    await deliverFCMPush(payload);

    expect(mocks.update).toHaveBeenCalledWith({
      where: { id: "device-1" },
      data: expect.objectContaining({ isActive: true, lastFailureReason: "UNAVAILABLE" })
    });
  });
});

describe("push fan-out", () => {
  it("publishes to realtime and both device transports", async () => {
    configureFCM();
    mocks.findFirst.mockResolvedValue({ id: "user-1" });
    mocks.findMany.mockResolvedValue([]);
    stubFetch({ status: 200, body: "{}" });

    await sendPushToUser(payload);

    expect(mocks.realtime).toHaveBeenCalledWith("user-1", expect.objectContaining({ type: "notification" }));
    expect(mocks.apns).toHaveBeenCalledWith(payload);
  });

  it("sends nothing for a deactivated account", async () => {
    mocks.findFirst.mockResolvedValue(null);

    await sendPushToUser(payload);

    expect(mocks.realtime).not.toHaveBeenCalled();
    expect(mocks.apns).not.toHaveBeenCalled();
  });
});
