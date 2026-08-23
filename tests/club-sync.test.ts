import { describe, expect, it } from "vitest";

import {
  normalizeClubAddressIdentity,
  normalizeClubIdentityText,
  normalizeClubSyncRecord,
  scoreClubCourtMatch
} from "@/lib/club-sync";
import {
  applyManualCourtOverridesForSync,
  buildCourtSyncCandidateWhere,
  resolveSyncedCourtStatus,
  shouldSyncCourtMetroLinks
} from "@/server/club-sync";

describe("club sync moderation locks", () => {
  it("keeps manually overridden fields and their normalized identities out of sync updates", () => {
    expect(
      applyManualCourtOverridesForSync(["name", "phone", "metroIds"], {
        name: "Импортное имя",
        normalizedName: "импортное имя",
        phone: "+70000000000",
        bookingUrl: "https://example.com/book"
      })
    ).toEqual({ bookingUrl: "https://example.com/book" });
  });

  it("does not reactivate a status changed by a moderator", () => {
    expect(resolveSyncedCourtStatus("hidden", true)).toBe("hidden");
    expect(resolveSyncedCourtStatus("archived", true)).toBe("archived");
    expect(resolveSyncedCourtStatus("hidden", false)).toBe("needs_review");
  });

  it("does not replace metro links after a moderator locks them", () => {
    expect(shouldSyncCourtMetroLinks(["name", "metroIds"])).toBe(false);
    expect(shouldSyncCourtMetroLinks(["name"])).toBe(true);
  });

  it("loads a stable source id across cities after a moderator changes city", () => {
    expect(
      buildCourtSyncCandidateWhere("Москва", [
        { sourceType: "yandex-places", sourceExternalId: "stable-123" },
        { sourceType: "yandex-places", sourceExternalId: "stable-123" }
      ])
    ).toEqual({
      OR: [
        { city: "Москва" },
        { sourceType: "yandex-places", sourceExternalId: "stable-123" }
      ]
    });
  });
});

describe("club sync normalization", () => {
  it("normalizes external club records into the court contract", () => {
    const record = normalizeClubSyncRecord(
      {
        sourceType: "Yandex Places",
        sourceExternalId: "123",
        name: "Спортивный клуб «Центр Тенниса»",
        address: "Санкт-Петербург; Лиговский проспект, дом 50",
        sports: "большой теннис|падел",
        phone: "+7 (812) 123-45-67",
        websiteUrl: "https://example.com/club#contacts",
        amenities: "Душевые|Парковка",
        photoUrls: "https://example.com/1.jpg|https://example.com/2.jpg",
        locationLat: 59.9315,
        locationLng: 30.3609
      },
      "Санкт-Петербург"
    );

    expect(record).not.toBeNull();
    expect(record?.sourceType).toBe("yandex_places");
    expect(record?.sports).toEqual(["tennis", "padel"]);
    expect(record?.phone).toBe("78121234567");
    expect(record?.district).toBe("central");
    expect(record?.photoUrls).toHaveLength(2);
    expect(record?.syncHash).toMatch(/^[a-f0-9]{64}$/);
  });

  it("keeps identity normalization stable for club names and addresses", () => {
    expect(normalizeClubIdentityText("ООО Теннисный клуб Северная Академия")).toBe("северная");
    expect(normalizeClubAddressIdentity("г. Санкт-Петербург, проспект Испытателей, дом 10")).toBe("испытателей 10");
  });
});

describe("club sync matching", () => {
  const incoming = normalizeClubSyncRecord(
    {
      sourceType: "yandex-places",
      sourceExternalId: "ym-1",
      name: "Центр тенниса",
      address: "Лиговский проспект, 50",
      sports: ["tennis"],
      locationLat: 59.9315,
      locationLng: 30.3609
    },
    "Санкт-Петербург"
  );

  it("matches by external id with full confidence", () => {
    expect(incoming).not.toBeNull();
    const score = scoreClubCourtMatch(
      {
        id: "court-1",
        name: "Другое имя",
        address: "Другой адрес",
        city: "Санкт-Петербург",
        sourceType: "yandex-places",
        sourceExternalId: "ym-1",
        locationLat: 59,
        locationLng: 30
      },
      incoming!
    );

    expect(score).toEqual({ confidence: 1, reason: "external_id" });
  });

  it("does not match conflicting ids from the same source through shared phone or website", () => {
    const record = normalizeClubSyncRecord(
      {
        sourceType: "xlsx-import",
        sourceExternalId: "club-b",
        name: "Филиал Б",
        address: "Тверская улица, 2",
        sports: ["tennis"],
        phone: "+7 495 000-00-00",
        websiteUrl: "https://chain.example/clubs",
        locationLat: 55.765,
        locationLng: 37.61
      },
      "Москва"
    );

    expect(record).not.toBeNull();
    expect(
      scoreClubCourtMatch(
        {
          id: "court-a",
          name: "Филиал А",
          address: "Тверская улица, 1",
          city: "Москва",
          sourceType: "xlsx-import",
          sourceExternalId: "club-a",
          phone: "+7 495 000-00-00",
          websiteUrl: "https://chain.example/clubs",
          locationLat: 55.764,
          locationLng: 37.61
        },
        record!
      )
    ).toEqual({ confidence: 0, reason: "external_id_conflict" });
  });

  it("matches by normalized name and address when there is no external id", () => {
    expect(incoming).not.toBeNull();
    const score = scoreClubCourtMatch(
      {
        id: "court-1",
        name: "Теннисный клуб Центр тенниса",
        address: "Санкт-Петербург, Лиговский пр., д. 50",
        city: "Санкт-Петербург",
        sourceType: "xlsx-import",
        sourceExternalId: null,
        normalizedName: normalizeClubIdentityText("Теннисный клуб Центр тенниса"),
        normalizedAddress: normalizeClubAddressIdentity("Санкт-Петербург, Лиговский пр., д. 50"),
        locationLat: 59.93151,
        locationLng: 30.36091
      },
      incoming!
    );

    expect(score.confidence).toBeGreaterThanOrEqual(0.88);
    expect(["name_address", "similar_name_address"]).toContain(score.reason);
  });

  it("matches a strong identity across sources even when both have different ids", () => {
    expect(incoming).not.toBeNull();
    const score = scoreClubCourtMatch(
      {
        id: "court-cross-source",
        name: "Теннисный клуб Центр тенниса",
        address: "Санкт-Петербург, Лиговский пр., д. 50",
        city: "Санкт-Петербург",
        sourceType: "xlsx-import",
        sourceExternalId: "xlsx-club-1",
        normalizedName: normalizeClubIdentityText("Теннисный клуб Центр тенниса"),
        normalizedAddress: normalizeClubAddressIdentity("Санкт-Петербург, Лиговский пр., д. 50"),
        locationLat: 59.93151,
        locationLng: 30.36091
      },
      incoming!
    );

    expect(score.confidence).toBeGreaterThanOrEqual(0.88);
    expect(["name_address", "similar_name_address"]).toContain(score.reason);
  });

  it("does not merge different clubs only because they share an address", () => {
    const freshTennis = normalizeClubSyncRecord(
      {
        sourceType: "xlsx-import",
        sourceExternalId: "fresh-tennis::выборгское ш., 6::санкт-петербург",
        name: "Fresh-tennis",
        address: "Выборгское ш., 6",
        sports: ["tennis"],
        phone: "+7 (812) 210-40-97",
        websiteUrl: "https://fresh-tennis.ru",
        locationLat: 60.208519,
        locationLng: 29.992745
      },
      "Санкт-Петербург"
    );

    expect(freshTennis).not.toBeNull();
    const score = scoreClubCourtMatch(
      {
        id: "court-fresh-fitness",
        name: "Fresh-fitness",
        address: "Выборгское ш., 6",
        city: "Санкт-Петербург",
        sourceType: "xlsx-import",
        sourceExternalId: "fresh-fitness::выборгское ш., 6::санкт-петербург",
        normalizedName: normalizeClubIdentityText("Fresh-fitness"),
        normalizedAddress: normalizeClubAddressIdentity("Выборгское ш., 6"),
        phone: "78122238903",
        websiteUrl: "https://fresh-fit.ru",
        locationLat: 60.208519,
        locationLng: 29.992745
      },
      freshTennis!
    );

    expect(score).toEqual({ confidence: 0, reason: "external_id_conflict" });
  });
});
