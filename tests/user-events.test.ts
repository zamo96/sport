import { describe, expect, it } from "vitest";

import { isClientReportableEventType } from "@/lib/user-events";
import { userEventsSchema } from "@/lib/validators";

describe("client event ingest", () => {
  it("accepts a batch of client-reportable events", () => {
    const parsed = userEventsSchema.parse({
      events: [
        { type: "app_open" },
        { type: "push_opened", deliveryId: "delivery-1" },
        { type: "discover_view", context: { view: "hot", count: 4, empty: false } }
      ]
    });

    expect(parsed.events).toHaveLength(3);
  });

  it("rejects server-only event types coming from a device", () => {
    for (const type of ["push_sent", "swipe", "match_created", "push_converted"]) {
      expect(isClientReportableEventType(type)).toBe(false);
      expect(() => userEventsSchema.parse({ events: [{ type }] })).toThrow();
    }
  });

  it("rejects empty and oversized batches", () => {
    expect(() => userEventsSchema.parse({ events: [] })).toThrow();
    expect(() =>
      userEventsSchema.parse({ events: Array.from({ length: 21 }, () => ({ type: "app_open" })) })
    ).toThrow();
  });

  it("rejects unknown fields", () => {
    expect(() => userEventsSchema.parse({ events: [{ type: "app_open", userId: "someone-else" }] })).toThrow();
  });
});
