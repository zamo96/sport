import { afterEach, describe, expect, it } from "vitest";

import { analyzeClubWebsiteWithLlm, isClubWebsiteLlmAnalystEnabled } from "@/lib/club-website-llm-analyst";
import type { ClubWebsiteSnapshot } from "@/lib/club-website";

const originalEnv = {
  CLUB_SYNC_ANALYST_MODE: process.env.CLUB_SYNC_ANALYST_MODE,
  CLUB_SYNC_LLM_ANALYST: process.env.CLUB_SYNC_LLM_ANALYST,
  OPENAI_API_KEY: process.env.OPENAI_API_KEY
};

const snapshot = {
  url: "https://club.example.com/",
  contentHash: "hash",
  title: "Club",
  description: null,
  analysisText: "Телефон +7 (812) 111-22-33",
  textSample: "Телефон +7 (812) 111-22-33",
  detectedPhones: ["78121112233"],
  detectedBookingUrls: [],
  closureSignals: [],
  phoneEvidence: [],
  bookingUrlEvidence: [],
  closureSignalEvidence: []
} satisfies ClubWebsiteSnapshot;

describe("club website LLM analyst", () => {
  afterEach(() => {
    restoreEnvValue("CLUB_SYNC_ANALYST_MODE", originalEnv.CLUB_SYNC_ANALYST_MODE);
    restoreEnvValue("CLUB_SYNC_LLM_ANALYST", originalEnv.CLUB_SYNC_LLM_ANALYST);
    restoreEnvValue("OPENAI_API_KEY", originalEnv.OPENAI_API_KEY);
  });

  it("is disabled by default", async () => {
    delete process.env.CLUB_SYNC_ANALYST_MODE;
    delete process.env.CLUB_SYNC_LLM_ANALYST;

    expect(isClubWebsiteLlmAnalystEnabled()).toBe(false);

    const result = await analyzeClubWebsiteWithLlm({
      analystInput: {
        court: {
          name: "Club",
          address: "СПб",
          phone: null,
          workingHours: null,
          bookingUrl: null,
          supportedSports: ["tennis"],
          about: null
        },
        snapshot,
        changed: false
      }
    });

    expect(result).toMatchObject({
      status: "disabled",
      review: null,
      errorMessage: null
    });
  });

  it("reports configuration failure when enabled without an API key", async () => {
    process.env.CLUB_SYNC_ANALYST_MODE = "hybrid";
    delete process.env.OPENAI_API_KEY;

    const result = await analyzeClubWebsiteWithLlm({
      analystInput: {
        court: {
          name: "Club",
          address: "СПб",
          phone: null,
          workingHours: null,
          bookingUrl: null,
          supportedSports: ["tennis"],
          about: null
        },
        snapshot,
        changed: false
      }
    });

    expect(result.status).toBe("failed");
    expect(result.errorMessage).toContain("OPENAI_API_KEY");
  });
});

function restoreEnvValue(key: string, value: string | undefined) {
  if (value === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = value;
  }
}
