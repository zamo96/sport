import { describe, expect, it } from "vitest";

import {
  assertAllowedClubReplacementCity,
  buildCityClubReplacementPlan,
  SAINT_PETERSBURG_CITY
} from "@/lib/club-city-replacement";

describe("city club replacement", () => {
  it("hard-blocks any city except Saint Petersburg", () => {
    expect(() => assertAllowedClubReplacementCity(SAINT_PETERSBURG_CITY)).not.toThrow();
    expect(() => assertAllowedClubReplacementCity("Москва")).toThrow(/только.*Санкт-Петербург/i);
  });

  it("retains an id only for a unique exact normalized identity", () => {
    const plan = buildCityClubReplacementPlan(
      [
        { id: "same", name: "Теннисный клуб Север", address: "ул. Спортивная, 1" },
        { id: "old", name: "Старый клуб", address: "Невский проспект, 2" }
      ],
      [
        {
          name: "Клуб «Север»",
          address: "улица Спортивная, 1",
          sourceExternalId: "yandex-org:1"
        },
        { name: "Новый клуб", address: "Лиговский проспект, 3", sourceExternalId: "yandex-org:2" }
      ]
    );

    expect(plan).toEqual({
      matches: [{ courtId: "same", incomingIndex: 0 }],
      createIndexes: [1],
      retireCourtIds: ["old"]
    });
  });

  it("does not guess when an exact identity is ambiguous", () => {
    const plan = buildCityClubReplacementPlan(
      [
        { id: "a", name: "Север", address: "Спортивная, 1" },
        { id: "b", name: "Север", address: "Спортивная, 1" }
      ],
      [{ name: "Север", address: "Спортивная, 1", sourceExternalId: "yandex-org:1" }]
    );

    expect(plan.matches).toEqual([]);
    expect(plan.createIndexes).toEqual([0]);
    expect(plan.retireCourtIds).toEqual(["a", "b"]);
  });

  it("retains distinct canonical clubs by source id even when identity is ambiguous", () => {
    const plan = buildCityClubReplacementPlan(
      [
        {
          id: "a",
          name: "Север",
          address: "Спортивная, 1",
          sourceExternalId: "yandex-org:1"
        },
        {
          id: "b",
          name: "Север",
          address: "Спортивная, 1",
          sourceExternalId: "yandex-org:2"
        }
      ],
      [
        { name: "Север", address: "Спортивная, 1", sourceExternalId: "yandex-org:1" },
        { name: "Север", address: "Спортивная, 1", sourceExternalId: "yandex-org:2" }
      ]
    );

    expect(plan).toEqual({
      matches: [
        { courtId: "a", incomingIndex: 0 },
        { courtId: "b", incomingIndex: 1 }
      ],
      createIndexes: [],
      retireCourtIds: []
    });
  });

  it("rejects duplicate source ids before cutover", () => {
    expect(() =>
      buildCityClubReplacementPlan([], [
        { name: "A", address: "1", sourceExternalId: "yandex-org:1" },
        { name: "B", address: "2", sourceExternalId: "yandex-org:1" }
      ])
    ).toThrow(/Дублирующийся source_external_id/);
  });
});
