import { describe, expect, it } from "vitest";

import { analyzeClubWebsite } from "@/lib/club-website-analyst";
import type { ClubWebsiteSnapshot } from "@/lib/club-website";

const baseSnapshot = {
  url: "https://club.example.com/",
  contentHash: "hash",
  title: "Club",
  description: null,
  analysisText: "Club text",
  textSample: "Club text",
  detectedPhones: [],
  detectedBookingUrls: [],
  closureSignals: [],
  phoneEvidence: [],
  bookingUrlEvidence: [],
  closureSignalEvidence: []
} satisfies ClubWebsiteSnapshot;

describe("club website analyst", () => {
  it("routes phone changes to manual review with evidence", () => {
    const review = analyzeClubWebsite({
      court: {
        name: "Fresh-tennis",
        phone: "78122104097",
        bookingUrl: null
      },
      snapshot: {
        ...baseSnapshot,
        detectedPhones: ["78123341444"],
        phoneEvidence: [
          {
            value: "78123341444",
            source: "tel_link",
            confidence: 0.96,
            snippet: "+7(812)334-14-44"
          }
        ]
      },
      changed: false
    });

    expect(review.decisions).toEqual([
      expect.objectContaining({
        field: "phone",
        action: "review",
        risk: "medium",
        reason: "phone_changed_needs_review"
      })
    ]);
  });

  it("auto-applies high-confidence same-host booking links", () => {
    const review = analyzeClubWebsite({
      court: {
        name: "Club",
        phone: null,
        bookingUrl: null
      },
      snapshot: {
        ...baseSnapshot,
        detectedBookingUrls: ["https://club.example.com/raspisanie"],
        bookingUrlEvidence: [
          {
            value: "https://club.example.com/raspisanie",
            source: "booking_link",
            confidence: 0.9,
            snippet: "Расписание",
            sameHost: true
          }
        ]
      },
      changed: false
    });

    expect(review.decisions).toEqual([
      expect.objectContaining({
        field: "bookingUrl",
        action: "apply",
        risk: "low",
        reason: "same_host_booking_link"
      })
    ]);
  });

  it("requires review for closure signals", () => {
    const review = analyzeClubWebsite({
      court: {
        name: "Club",
        phone: null,
        bookingUrl: null
      },
      snapshot: {
        ...baseSnapshot,
        closureSignals: ["временно закрыт"],
        closureSignalEvidence: [
          {
            value: "временно закрыт",
            source: "closure_text",
            confidence: 0.72,
            snippet: "Клуб временно закрыт на ремонт"
          }
        ]
      },
      changed: false
    });

    expect(review.decisions).toEqual([
      expect.objectContaining({
        field: "closureSignals",
        action: "review",
        risk: "high"
      })
    ]);
  });
});
