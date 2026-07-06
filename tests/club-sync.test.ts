import { describe, expect, it } from "vitest";

import {
  normalizeClubAddressIdentity,
  normalizeClubIdentityText,
  normalizeClubSyncRecord,
  scoreClubCourtMatch
} from "@/lib/club-sync";

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

    expect(score).toEqual({ confidence: 0.72, reason: "same_address_needs_review" });
  });
});
