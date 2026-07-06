import { describe, expect, it } from "vitest";

import { type ClubSyncReport, formatClubSyncReportMarkdown } from "@/server/club-sync-report";

describe("club sync report", () => {
  it("formats counters, applied changes, pending review, and failed websites", () => {
    const report = {
      run: {
        id: "run-1",
        sourceType: "club-website",
        city: "Санкт-Петербург",
        status: "completed",
        startedAt: "2026-07-04T16:30:12.594Z",
        finishedAt: "2026-07-04T16:30:20.163Z",
        durationMs: 7569,
        errorMessage: null
      },
      counters: {
        fetched: 0,
        created: 0,
        updated: 0,
        unchanged: 0,
        proposed: 1,
        hidden: 0,
        websiteChecked: 2,
        websiteChanged: 1,
        websiteFailed: 1
      },
      websiteChecks: {
        total: 2,
        byStatus: {
          changed: 1,
          failed: 1
        },
        changed: [
          {
            id: "check-1",
            courtId: "court-1",
            courtName: "Fresh-tennis",
            url: "https://fresh-tennis.ru/",
            status: "changed",
            checkedAt: "2026-07-04T16:30:20.000Z",
            httpStatus: 200,
            changed: true,
            errorMessage: null,
            detectedPhones: ["78123341444"],
            detectedBookingUrls: ["https://fresh-fit.ru/raspisanie"],
            closureSignals: [],
            analystProvider: "rules+openai",
            analystModel: "gpt-4.1-mini",
            analystStatus: "completed",
            analystErrorMessage: null,
            screenshotStatus: "disabled",
            screenshotErrorMessage: null
          }
        ],
        failed: [
          {
            id: "check-2",
            courtId: "court-2",
            courtName: "Demo club",
            url: "https://example.com/demo",
            status: "failed",
            checkedAt: "2026-07-04T16:30:21.000Z",
            httpStatus: null,
            changed: false,
            errorMessage: "Website fetch failed: 404 Not Found",
            detectedPhones: [],
            detectedBookingUrls: [],
            closureSignals: [],
            analystProvider: null,
            analystModel: null,
            analystStatus: null,
            analystErrorMessage: null,
            screenshotStatus: null,
            screenshotErrorMessage: null
          }
        ],
        analystFailed: []
      },
      changes: {
        total: 1,
        byStatus: {
          applied: 1
        },
        applied: [
          {
            id: "change-1",
            courtId: "court-1",
            courtName: "Fresh-tennis",
            action: "website_update",
            status: "applied",
            confidence: 0.82,
            reason: "website_detected_fields",
            createdAt: "2026-07-04T16:30:20.000Z",
            appliedAt: "2026-07-04T16:30:20.000Z",
            proposedFields: [
              {
                field: "phone",
                beforeValue: "78122104097",
                afterValue: "78123341444",
                confidence: 0.96,
                autoApply: false,
                reason: "phone_changed_needs_review",
                evidence: [
                  {
                    source: "tel_link",
                    confidence: 0.96,
                    snippet: "+7(812)334-14-44",
                    value: "78123341444"
                  }
                ]
              },
              {
                field: "bookingUrl",
                beforeValue: null,
                afterValue: "https://fresh-fit.ru/raspisanie",
                confidence: 0.9,
                autoApply: true,
                reason: "same_host_booking_link",
                evidence: [
                  {
                    source: "booking_link",
                    confidence: 0.9,
                    snippet: "Расписание",
                    value: "https://fresh-fit.ru/raspisanie"
                  }
                ]
              }
            ],
            before: {
              bookingUrl: null
            },
            after: {
              bookingUrl: "https://fresh-fit.ru/raspisanie"
            }
          }
        ],
        pending: [],
        other: []
      },
      notes: [
        "1 website checks failed and need source cleanup or retry.",
        "1 changes were applied automatically."
      ]
    } satisfies ClubSyncReport;

    const markdown = formatClubSyncReportMarkdown(report);

    expect(markdown).toContain("Run: `run-1`");
    expect(markdown).toContain("Websites checked: 2");
    expect(markdown).toContain("Fresh-tennis: website_update");
    expect(markdown).toContain(
      "phone: +7 (812) 210-40-97 -> +7 (812) 334-14-44 (review, confidence 0.96"
    );
    expect(markdown).toContain(
      "bookingUrl: (empty) -> https://fresh-fit.ru/raspisanie (auto, confidence 0.90"
    );
    expect(markdown).toContain("evidence: phone/tel_link 0.96 \"+7(812)334-14-44\"");
    expect(markdown).toContain("Demo club: failed https://example.com/demo - Website fetch failed: 404 Not Found");
    expect(markdown).toContain("1 changes were applied automatically.");
  });
});
