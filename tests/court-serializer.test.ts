import { describe, expect, it } from "vitest";

import { serializeCourt } from "@/server/serializers";

type SerializableCourt = Parameters<typeof serializeCourt>[0];

function makeCourt(overrides: Record<string, unknown> = {}): SerializableCourt {
  return {
    id: "court-1",
    name: "Ракета",
    address: "Юго-Западная, 1",
    city: "Санкт-Петербург",
    district: "kirovsky",
    locationLat: 59.85,
    locationLng: 30.27,
    distanceKm: null,
    nearestMetro: null,
    metroLinks: [],
    supportedSports: ["tennis", "padel"],
    phone: null,
    workingHours: null,
    yandexMapsUrl: null,
    websiteUrl: null,
    bookingUrl: null,
    about: null,
    amenities: ["Крытый", "Душ", "Парковка"],
    messengerType: null,
    messengerUrl: null,
    photoUrl: null,
    photoUrls: [],
    priceRange: "$$",
    rating: null,
    isMember: false,
    _count: {
      members: 0
    },
    members: [],
    ...overrides
  } as unknown as SerializableCourt;
}

describe("serializeCourt", () => {
  it("includes active search counters and preview users", () => {
    const court = makeCourt({
      activeSearchesCount: 2,
      activeSearchPlayersCount: 3,
      activeSearchPreviewUsers: [
        {
          id: "user-1",
          name: "Матвей",
          age: 29,
          city: "Санкт-Петербург",
          district: "kirovsky",
          avatarUrl: "/uploads/avatar.jpg"
        }
      ]
    });

    expect(serializeCourt(court)).toMatchObject({
      activeSearchesCount: 2,
      activeSearchPlayersCount: 3,
      activeSearchPreviewUsers: [
        {
          id: "user-1",
          name: "Матвей"
        }
      ]
    });
  });

  it("defaults active search counters for legacy court payloads", () => {
    expect(serializeCourt(makeCourt())).toMatchObject({
      activeSearchesCount: 0,
      activeSearchPlayersCount: 0,
      activeSearchPreviewUsers: []
    });
  });
});
