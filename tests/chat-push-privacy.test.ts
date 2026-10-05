import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  userFindFirst: vi.fn(),
  deliverAPNSPush: vi.fn(),
  deliverFCMPush: vi.fn(),
  publishRealtimeEvent: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({ prisma: { user: { findFirst: mocks.userFindFirst } } }));
vi.mock("@/lib/apns", () => ({ deliverAPNSPush: mocks.deliverAPNSPush }));
vi.mock("@/lib/fcm", () => ({ deliverFCMPush: mocks.deliverFCMPush }));
vi.mock("@/server/realtime", () => ({ publishRealtimeEvent: mocks.publishRealtimeEvent }));

import { sendPushToUser } from "@/lib/push";
import { CHAT_PUSH_BODY, chatMessagePushContent } from "@/server/chat-media";

const secret = "Встречаемся у третьего корта, код от калитки 4471";

describe("chat pushes keep the message on our servers", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.userFindFirst.mockResolvedValue({ id: "player-2" });
  });

  it("never puts the message text into the device push", () => {
    const content = chatMessagePushContent({ text: secret, attachments: [] });
    expect(content.body).toBe(CHAT_PUSH_BODY);
    expect(content.body).not.toContain("корта");
    expect(content.inAppBody).toBe(secret);
  });

  it("sends Apple and Google only the neutral text; the preview goes to the in-app banner", async () => {
    await sendPushToUser({
      userId: "player-2",
      title: "Новое сообщение от Анны",
      ...chatMessagePushContent({ text: secret, attachments: [] }),
      href: "/inbox/match-1"
    });

    for (const deliver of [mocks.deliverAPNSPush, mocks.deliverFCMPush]) {
      expect(deliver).toHaveBeenCalledOnce();
      expect(JSON.stringify(deliver.mock.calls[0][0].body)).not.toContain("корта");
      expect(deliver.mock.calls[0][0].body).toBe(CHAT_PUSH_BODY);
    }
    expect(mocks.publishRealtimeEvent).toHaveBeenCalledWith("player-2", expect.objectContaining({ type: "notification", body: secret }));
  });

  it("keeps other notifications unchanged", async () => {
    await sendPushToUser({ userId: "player-2", title: "Игра завтра", body: "Корт 3, 19:00", href: "/play" });

    expect(mocks.deliverAPNSPush.mock.calls[0][0].body).toBe("Корт 3, 19:00");
    expect(mocks.publishRealtimeEvent).toHaveBeenCalledWith("player-2", expect.objectContaining({ body: "Корт 3, 19:00" }));
  });
});
