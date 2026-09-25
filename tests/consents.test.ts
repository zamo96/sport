import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  findUniqueOrThrow: vi.fn(),
  updateUser: vi.fn(),
  createConsents: vi.fn(),
  createAcceptances: vi.fn(),
  deleteEvents: vi.fn()
}));

vi.mock("@/lib/prisma", () => {
  const tx = {
    user: { findUniqueOrThrow: mocks.findUniqueOrThrow, update: mocks.updateUser },
    userConsent: { createMany: mocks.createConsents },
    userAgreementAcceptance: { createMany: mocks.createAcceptances },
    userEvent: { deleteMany: mocks.deleteEvents }
  };
  return { prisma: { ...tx, $transaction: (run: (client: typeof tx) => unknown) => run(tx) } };
});

import {
  buildLatestUserAgreementPayload,
  buildUserAgreementAcceptanceRecord,
  LEGACY_USER_AGREEMENT_VERSION,
  PREVIOUS_USER_AGREEMENT_VERSION,
  PROFILE_VISIBILITY_CONSENT_VERSION,
  USER_AGREEMENT_VERSION
} from "@/lib/legal-contract";
import {
  buildConsentState,
  initialProfileVisibility,
  isPubliclyVisible,
  publicProfileWhere,
  redactPublicPreview,
  redactPublicUserRecord
} from "@/lib/profile-visibility";
import { consentUpdateSchema, verifySchema } from "@/lib/validators";
import { applyConsentUpdate, ConsentUpdateError } from "@/server/consents";

const storedUser = {
  id: "user-1",
  showOnMap: true,
  profileVisibility: "legacy" as const,
  profileVisibleToGuests: false,
  profileShowsBio: false,
  profileShowsPhotos: false,
  profileShowsVideos: false,
  profileShowsSearches: false,
  analyticsConsent: false,
  consentFullName: null,
  agreementVersion: PREVIOUS_USER_AGREEMENT_VERSION
};

describe("profile visibility rules", () => {
  it("keeps accounts that predate the consent screen visible until they answer", () => {
    expect(isPubliclyVisible({ profileVisibility: "legacy" }, "guest")).toBe(true);
    expect(isPubliclyVisible({ profileVisibility: "legacy" }, "registered", { requireSearches: true })).toBe(true);
  });

  it("never shows accounts that have not answered or declined", () => {
    for (const state of ["pending", "hidden"] as const) {
      expect(isPubliclyVisible({ profileVisibility: state, profileVisibleToGuests: true }, "registered")).toBe(false);
    }
  });

  it("shows a consented profile to guests only with the guest permission", () => {
    const registeredOnly = { profileVisibility: "visible" as const, profileVisibleToGuests: false };
    expect(isPubliclyVisible(registeredOnly, "registered")).toBe(true);
    expect(isPubliclyVisible(registeredOnly, "guest")).toBe(false);
    expect(isPubliclyVisible({ ...registeredOnly, profileVisibleToGuests: true }, "guest")).toBe(true);
  });

  it("requires the searches permission for search listings", () => {
    const visible = { profileVisibility: "visible" as const, profileShowsSearches: false };
    expect(isPubliclyVisible(visible, "registered", { requireSearches: true })).toBe(false);
    expect(isPubliclyVisible({ ...visible, profileShowsSearches: true }, "registered", { requireSearches: true })).toBe(true);
  });

  it("builds the same rule as a Prisma filter that can sit next to other user conditions", () => {
    expect(publicProfileWhere("guest", { requireSearches: true })).toEqual({
      AND: [
        {
          OR: [
            { profileVisibility: "legacy" },
            { profileVisibility: "visible", profileVisibleToGuests: true, profileShowsSearches: true }
          ]
        }
      ]
    });
    expect(publicProfileWhere("registered")).toEqual({
      AND: [{ OR: [{ profileVisibility: "legacy" }, { profileVisibility: "visible" }] }]
    });
  });

  it("removes groups the owner did not allow from public cards", () => {
    const preview = {
      bio: "Играю по выходным",
      avatarUrl: "https://cdn/p1.jpg",
      profilePhotoUrls: ["https://cdn/p1.jpg"],
      profileVideoUrls: ["https://cdn/v1.mp4"],
      profileMediaOrder: ["https://cdn/v1.mp4", "https://cdn/p1.jpg"],
      gameSearches: [{ id: "s1" }]
    };
    const redacted = redactPublicPreview(preview, { profileVisibility: "visible", profileShowsVideos: true });
    expect(redacted).toEqual({
      bio: null,
      avatarUrl: null,
      profilePhotoUrls: [],
      profileVideoUrls: ["https://cdn/v1.mp4"],
      profileMediaOrder: ["https://cdn/v1.mp4"],
      gameSearches: []
    });
    expect(redactPublicPreview(preview, { profileVisibility: "legacy" })).toBe(preview);
  });

  it("redacts database records used directly by the web search page", () => {
    const record = { id: "u", profileVisibility: "visible" as const, profileShowsPhotos: true, bio: "текст", avatarUrl: "a", profilePhotoUrls: ["a"], profileVideoUrls: ["v"], profileMediaOrder: ["v", "a"] };
    expect(redactPublicUserRecord(record)).toMatchObject({ id: "u", bio: null, avatarUrl: "a", profilePhotoUrls: ["a"], profileVideoUrls: [], profileMediaOrder: ["a"] });
  });
});

describe("consent state for clients", () => {
  it("asks legacy accounts and accounts on an old agreement to review", () => {
    const state = buildConsentState({ ...storedUser, profileVisibility: "legacy" });
    expect(state.termsUpdateRequired).toBe(true);
    expect(state.reviewRequired).toBe(true);
  });

  it("does not ask again once the person answered and accepted the current agreement", () => {
    for (const profileVisibility of ["visible", "hidden"] as const) {
      const state = buildConsentState({ ...storedUser, profileVisibility, agreementVersion: USER_AGREEMENT_VERSION });
      expect(state.reviewRequired).toBe(false);
    }
  });

  it("prefills the name field from the profile until a consent stores its own name", () => {
    expect(buildConsentState({ ...storedUser, name: "  Анна   Козлова " }).fullName).toBe("Анна Козлова");
    expect(buildConsentState({ ...storedUser, name: "Анна" }).fullName).toBe("Анна");
    expect(buildConsentState({ ...storedUser, name: "Анна", consentFullName: "Козлова Анна" }).fullName).toBe("Козлова Анна");
    expect(buildConsentState({ ...storedUser, name: "   " }).fullName).toBeNull();
  });

  it("new sign-ups from clients with the consent screen start hidden; older clients keep the old behaviour", () => {
    expect(initialProfileVisibility(true)).toBe("pending");
    expect(initialProfileVisibility(undefined)).toBeUndefined();
  });
});

describe("agreement acceptance no longer bundles personal-data consent", () => {
  it("records no personal-data consent for the current agreement", () => {
    const record = buildUserAgreementAcceptanceRecord({ userId: "u", source: "email_otp", agreementVersion: USER_AGREEMENT_VERSION });
    expect(record.personalDataConsentVersion).toBeNull();
  });

  it("keeps recording the bundled consent that older builds actually showed", () => {
    for (const version of [PREVIOUS_USER_AGREEMENT_VERSION, LEGACY_USER_AGREEMENT_VERSION] as const) {
      expect(buildUserAgreementAcceptanceRecord({ userId: "u", source: "apple", agreementVersion: version }).personalDataConsentVersion).toBe(version);
    }
  });

  it("accepts the consent-screen flag on sign-in", () => {
    const parsed = verifySchema.parse({ email: "a@b.ru", code: "123456", consentReview: true, userAgreement: buildLatestUserAgreementPayload() });
    expect(parsed.consentReview).toBe(true);
  });
});

describe("consent update payload", () => {
  it("requires a surname and first name for the profile consent", () => {
    const base = { source: "ios", profile: { decision: "visible" } };
    expect(consentUpdateSchema.safeParse({ ...base, profile: { ...base.profile, fullName: "Анна" } }).success).toBe(false);
    expect(consentUpdateSchema.safeParse({ ...base, profile: { ...base.profile, fullName: "Козлова  Анна" } }).data?.profile?.fullName).toBe("Козлова Анна");
    expect(consentUpdateSchema.safeParse({ ...base, profile: { ...base.profile, fullName: "Anna-Maria O'Neil" } }).success).toBe(true);
  });

  it("rejects an outdated agreement version and empty updates", () => {
    expect(consentUpdateSchema.safeParse({ source: "web", acceptAgreementVersion: PREVIOUS_USER_AGREEMENT_VERSION }).success).toBe(false);
    expect(consentUpdateSchema.safeParse({ source: "web" }).success).toBe(false);
    expect(consentUpdateSchema.safeParse({ source: "web", analytics: false }).success).toBe(true);
  });
});

describe("applyConsentUpdate", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.findUniqueOrThrow.mockResolvedValue(storedUser);
    mocks.updateUser.mockImplementation(async ({ data }) => ({ ...storedUser, ...data }));
  });

  it("records each consent separately with its own version and snapshot", async () => {
    await applyConsentUpdate(
      "user-1",
      {
        source: "ios",
        acceptAgreementVersion: USER_AGREEMENT_VERSION,
        profile: { decision: "visible", fullName: "Козлова Анна", visibleToGuests: true, showsBio: true, showsPhotos: true, showOnMap: false },
        analytics: true
      },
      { ip: "10.0.0.1", userAgent: "ios" }
    );

    expect(mocks.createAcceptances.mock.calls[0][0].data[0]).toMatchObject({
      agreementVersion: USER_AGREEMENT_VERSION,
      personalDataConsentVersion: null,
      acceptedVia: "consent_review_ios"
    });
    const rows = mocks.createConsents.mock.calls[0][0].data;
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      kind: "profile_visibility",
      version: PROFILE_VISIBILITY_CONSENT_VERSION,
      granted: true,
      fullName: "Козлова Анна",
      scope: { visibleToGuests: true, bio: true, photos: true, videos: false, searches: false, map: false },
      source: "ios",
      ipAddress: "10.0.0.1"
    });
    expect(rows[1]).toMatchObject({ kind: "analytics", granted: true });
    expect(mocks.updateUser.mock.calls[0][0].data).toMatchObject({
      agreementVersion: USER_AGREEMENT_VERSION,
      profileVisibility: "visible",
      consentFullName: "Козлова Анна",
      profileVisibleToGuests: true,
      profileShowsVideos: false,
      showOnMap: false,
      analyticsConsent: true
    });
    expect(mocks.deleteEvents).not.toHaveBeenCalled();
  });

  it("hides the profile and logs the refusal without asking for a name", async () => {
    await applyConsentUpdate("user-1", { source: "web", profile: { decision: "hidden" } });
    expect(mocks.updateUser.mock.calls[0][0].data).toEqual({ profileVisibility: "hidden" });
    expect(mocks.createConsents.mock.calls[0][0].data[0]).toMatchObject({ kind: "profile_visibility", granted: false });
  });

  it("refuses to show a profile without a name on file", async () => {
    await expect(applyConsentUpdate("user-1", { source: "web", profile: { decision: "visible" } })).rejects.toBeInstanceOf(ConsentUpdateError);
    expect(mocks.updateUser).not.toHaveBeenCalled();
  });

  it("reuses the stored name when only the scope changes", async () => {
    mocks.findUniqueOrThrow.mockResolvedValue({ ...storedUser, profileVisibility: "visible", consentFullName: "Козлова Анна" });
    await applyConsentUpdate("user-1", { source: "android", profile: { decision: "visible", showsPhotos: true } });
    expect(mocks.createConsents.mock.calls[0][0].data[0].fullName).toBe("Козлова Анна");
  });

  it("deletes stored analytics events when consent is withdrawn", async () => {
    await applyConsentUpdate("user-1", { source: "web", analytics: false });
    expect(mocks.deleteEvents).toHaveBeenCalledWith({ where: { userId: "user-1" } });
    expect(mocks.updateUser.mock.calls[0][0].data).toEqual({ analyticsConsent: false });
  });
});
