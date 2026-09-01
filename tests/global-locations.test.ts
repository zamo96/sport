import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  geoPlaceFindUnique: vi.fn(),
  geoPlaceUpsert: vi.fn(),
  serviceAreaUpsert: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    geoPlace: {
      findUnique: mocks.geoPlaceFindUnique,
      upsert: mocks.geoPlaceUpsert
    },
    serviceArea: { upsert: mocks.serviceAreaUpsert }
  }
}));

import {
  canonicalizeNominatimSearchResults,
  listCountries,
  isNominatimSettlementResult,
  nominatimProviderPlaceId,
  reverseGeocode,
  searchCities,
  selectCanonicalNominatimSettlement,
  shouldPreserveCurrentGlobalLocation
} from "@/server/locations";
import { catalogCitiesForCountry, findNearestCatalogCity, searchCatalogCities } from "@/server/world-city-catalog";

describe("global locations", () => {
  beforeEach(() => {
    mocks.geoPlaceUpsert.mockImplementation(async ({ create }: { create: Record<string, unknown> }) => ({
      ...create,
      createdAt: new Date("2026-08-31T00:00:00.000Z"),
      updatedAt: new Date("2026-08-31T00:00:00.000Z"),
      serviceArea: null
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    mocks.geoPlaceFindUnique.mockReset();
    mocks.geoPlaceUpsert.mockReset();
    mocks.serviceAreaUpsert.mockReset();
  });

  it("returns a localized complete country choice", () => {
    const countries = listCountries("ru", "Герм");
    expect(countries).toContainEqual({ code: "DE", name: "Германия", cityCount: expect.any(Number) });
  });

  it("only returns countries that have at least one packaged city", () => {
    const countries = listCountries("en");
    expect(countries.length).toBeGreaterThan(200);
    expect(countries.every((country) => country.cityCount > 0 && catalogCitiesForCountry(country.code).length > 0)).toBe(true);
    expect(countries.some((country) => country.code === "AQ")).toBe(false);
  });

  it("rejects unknown country codes before calling a provider", async () => {
    await expect(searchCities({ countryCode: "XX", query: "City" })).rejects.toThrow("Некорректный код страны");
  });

  it("returns known cities for a country without calling the external provider", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const places = await searchCities({ countryCode: "ru", query: "", limit: 4 });

    expect(fetchMock).not.toHaveBeenCalled();
    expect(places.map((place) => place.id)).toEqual([
      "legacy:ru:saint-petersburg",
      "legacy:ru:moscow",
      "simplemaps:1643399240",
      "simplemaps:1643582706"
    ]);
    expect(mocks.geoPlaceUpsert).toHaveBeenCalledTimes(2);
    expect(places.slice(2).every((place) => place.provider === "simplemaps")).toBe(true);
  });

  it("lists cities for Russia, the United States, and a city-state without a provider call", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const [russia, unitedStates, vatican] = await Promise.all([
      searchCities({ countryCode: "RU", query: "", limit: 5 }),
      searchCities({ countryCode: "US", query: "", limit: 5 }),
      searchCities({ countryCode: "VA", query: "", limit: 5 })
    ]);

    expect(russia.map((place) => place.city).slice(0, 2)).toEqual(["Санкт-Петербург", "Москва"]);
    expect(unitedStates.length).toBe(5);
    expect(russia.every((place) => place.recommendedLocale === "ru")).toBe(true);
    expect(unitedStates.every((place) => place.recommendedLocale === "en")).toBe(true);
    expect(vatican).toHaveLength(1);
    expect(vatican[0]).toMatchObject({ city: "Vatican City", countryCode: "VA", provider: "simplemaps" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("keeps same-name cities distinct by region and stable dataset ID", async () => {
    const places = await searchCities({ countryCode: "US", query: "Springfield", limit: 10 });
    expect(places.length).toBeGreaterThan(2);
    expect(new Set(places.map((place) => place.id)).size).toBe(places.length);
    expect(new Set(places.map((place) => place.region)).size).toBeGreaterThan(2);
    expect(places.every((place) => place.id.startsWith("simplemaps:") && place.provider === "simplemaps")).toBe(true);
  });

  it("ranks exact and prefix catalog matches before population and ignores diacritics", () => {
    const yorkMatches = searchCatalogCities("US", "York", 10);
    expect(yorkMatches[0].city).toBe("York");
    expect(yorkMatches.findIndex((city) => city.city === "New York")).toBeGreaterThan(0);

    const saoMatches = searchCatalogCities("BR", "Sao Paulo", 5);
    expect(saoMatches[0].city).toBe("São Paulo");
  });

  it("has a Cyrillic display name for every Russian catalog row", () => {
    const russianCities = catalogCitiesForCountry("RU");
    expect(russianCities.length).toBeGreaterThan(1_000);
    expect(russianCities.every((city) => /[А-ЯЁ]/i.test(city.city) && !/[A-Z]/i.test(city.city))).toBe(true);
    expect(russianCities).toContainEqual(expect.objectContaining({
      id: "1643832017",
      city: "Владивосток"
    }));
    expect(russianCities).toContainEqual(expect.objectContaining({
      id: "1643640451",
      city: "Каменск-Уральский"
    }));
  });

  it("finds the same Russian place by Cyrillic and Latin names", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const [cyrillicResults, latinResults] = await Promise.all([
      searchCities({ countryCode: "RU", query: "Новосибирск", limit: 5 }),
      searchCities({ countryCode: "RU", query: "Novosibirsk", limit: 5 })
    ]);

    expect(cyrillicResults[0]).toMatchObject({
      id: "simplemaps:1643399240",
      city: "Новосибирск",
      provider: "simplemaps"
    });
    expect(latinResults[0]).toMatchObject(cyrillicResults[0]);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("distinguishes Rostov-on-Don from Rostov Veliky and accepts common aliases", async () => {
    const queries = ["ростов-на-дону", "Rostov-on-Don", "Rostov on Don"];
    const specificResults = await Promise.all(
      queries.map((query) => searchCities({ countryCode: "RU", query, limit: 5 }))
    );

    for (const results of specificResults) {
      expect(results[0]).toMatchObject({
        id: "simplemaps:1643013518",
        city: "Ростов-на-Дону"
      });
    }

    const broadResults = await searchCities({ countryCode: "RU", query: "Ростов", limit: 10 });
    expect(broadResults[0]).toMatchObject({ id: "simplemaps:1643013518", city: "Ростов-на-Дону" });
    expect(broadResults).toContainEqual(expect.objectContaining({
      id: "simplemaps:1643848937",
      city: "Ростов Великий"
    }));
  });

  it("returns canonical Russian names for common Latin city spellings", async () => {
    const [vladivostok, kamensk] = await Promise.all([
      searchCities({ countryCode: "RU", query: "Vladivostok", limit: 5 }),
      searchCities({ countryCode: "RU", query: "Kamensk-Uralskiy", limit: 5 })
    ]);

    expect(vladivostok[0]).toMatchObject({
      id: "simplemaps:1643832017",
      city: "Владивосток"
    });
    expect(kamensk[0]).toMatchObject({
      id: "simplemaps:1643640451",
      city: "Каменск-Уральский"
    });
  });

  it("returns only Cyrillic city labels in the initial Russian list", async () => {
    const places = await searchCities({ countryCode: "RU", query: "", limit: 20 });
    expect(places).toHaveLength(20);
    expect(places.every((place) => /[А-ЯЁ]/i.test(place.city) && !/[A-Z]/i.test(place.city))).toBe(true);
    expect(places.slice(0, 2).map((place) => place.city)).toEqual(["Санкт-Петербург", "Москва"]);
  });

  it("does not query storage or the provider for a one-character city query", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(searchCities({ countryCode: "RU", query: "М" })).resolves.toEqual([]);
    expect(mocks.geoPlaceUpsert).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("protects a trusted global place from an old client city fallback", () => {
    expect(shouldPreserveCurrentGlobalLocation(undefined, "nominatim:relation:62422")).toBe(true);
    expect(shouldPreserveCurrentGlobalLocation(undefined, "legacy:ru:moscow")).toBe(false);
    expect(shouldPreserveCurrentGlobalLocation("legacy:ru:moscow", "nominatim:relation:62422")).toBe(false);
  });

  it("does not turn a POI address into a distinct city place", () => {
    const restaurant = {
      osm_type: "node",
      osm_id: 111,
      class: "amenity",
      type: "restaurant",
      addresstype: "amenity",
      lat: "52.5201",
      lon: "13.4051",
      address: { city: "Berlin", state: "Berlin", country: "Deutschland", country_code: "de" }
    };
    expect(isNominatimSettlementResult(restaurant)).toBe(false);
  });

  it("canonicalizes reverse results to the same settlement relation returned by search", () => {
    const reversePoi = {
      osm_type: "node",
      osm_id: 111,
      class: "amenity",
      type: "restaurant",
      addresstype: "amenity",
      lat: "52.5201",
      lon: "13.4051",
      address: { city: "Berlin", state: "Berlin", country: "Deutschland", country_code: "de" }
    };
    const berlinRelation = {
      osm_type: "relation",
      osm_id: 62422,
      class: "boundary",
      type: "administrative",
      addresstype: "city",
      lat: "52.5174",
      lon: "13.3951",
      address: { city: "Berlin", state: "Berlin", country: "Deutschland", country_code: "de" }
    };
    const unrelatedPoi = { ...reversePoi, osm_id: 222 };

    const canonical = selectCanonicalNominatimSettlement(reversePoi, [unrelatedPoi, berlinRelation]);
    expect(canonical).toBe(berlinRelation);
    expect(nominatimProviderPlaceId(canonical!)).toBe(nominatimProviderPlaceId(berlinRelation));
    expect(nominatimProviderPlaceId(canonical!)).toBe("relation:62422");
    expect(canonicalizeNominatimSearchResults([{ ...berlinRelation, osm_type: "node", osm_id: 333 }, berlinRelation])).toEqual([
      berlinRelation
    ]);
  });

  it("falls back to a trusted built-in city when reverse geocoding is unavailable", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    const place = await reverseGeocode({ latitude: 55.7558, longitude: 37.6173 });
    expect(place).toMatchObject({
      id: "legacy:ru:moscow",
      city: "Москва",
      coverage: { clubsEnabled: true, districtsEnabled: true }
    });
  });
  it("names a city worldwide from the packaged catalog when no geocoder is configured", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    const place = await reverseGeocode({ latitude: 55.0084, longitude: 82.9357 });
    expect(place).toMatchObject({
      id: "simplemaps:1643399240",
      countryCode: "RU",
      city: "Новосибирск",
      coverage: { isSupported: false }
    });
  });

  it("returns nothing when no catalog city is within reach", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    expect(await reverseGeocode({ latitude: 0, longitude: -140 })).toBeNull();
  });

  it("picks the closest catalog city and respects the radius", () => {
    expect(findNearestCatalogCity(52.52, 13.405, 100)).toMatchObject({ city: "Berlin", countryCode: "DE" });
    expect(findNearestCatalogCity(-33.8688, 151.2093, 100)).toMatchObject({ countryCode: "AU" });
    expect(findNearestCatalogCity(0, -140, 100)).toBeNull();
  });
});
