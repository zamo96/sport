import { describe, expect, it } from "vitest";

import {
  clubImportIdentityKey,
  groupClubImportRowsByCity,
  mergeClubImportRows,
  resolveClubImportSourceExternalId,
  saintPetersburgManualCourtsRetirementFilter,
  withInferredClubImportDistricts
} from "@/lib/club-import";

type TestClubRow = {
  city: string;
  name: string;
  address: string;
  sports: string[];
  websiteUrl: string | null;
  sourceExternalId?: string | null;
};

describe("club workbook import preparation", () => {
  it("prepares inferred Moscow districts before courts are inserted", () => {
    const [row] = withInferredClubImportDistricts([
      { district: null, lat: 55.7558, lng: 37.6173 }
    ]);

    expect(row.district).toBe("moscow_central");
  });

  it("merges sports for duplicate city, name and address rows", () => {
    const rows: TestClubRow[] = [
      {
        city: "Москва",
        name: "Спортцентр",
        address: "Ленинградский проспект, 1",
        sports: ["tennis"],
        websiteUrl: null
      },
      {
        city: " москва ",
        name: "СПОРТЦЕНТР",
        address: "Ленинградский   проспект, 1",
        sports: ["padel", "tennis"],
        websiteUrl: "https://example.test"
      }
    ];

    expect(mergeClubImportRows(rows)).toEqual([
      {
        ...rows[1],
        sports: ["tennis", "padel"]
      }
    ]);
  });

  it("groups rows by their own city and keeps preparation idempotent", () => {
    const rows: TestClubRow[] = [
      {
        city: "Санкт-Петербург",
        name: "Север",
        address: "Невский проспект, 1",
        sports: ["tennis"],
        websiteUrl: null
      },
      {
        city: "Москва",
        name: "Юг",
        address: "Тверская улица, 1",
        sports: ["padel"],
        websiteUrl: null
      },
      {
        city: "Москва",
        name: "Юг",
        address: "Тверская улица, 1",
        sports: ["tennis"],
        websiteUrl: null
      }
    ];

    const prepared = mergeClubImportRows(rows);
    expect(mergeClubImportRows(prepared)).toEqual(prepared);
    expect(groupClubImportRowsByCity(prepared)).toEqual([
      { city: "Санкт-Петербург", rows: [prepared[0]] },
      { city: "Москва", rows: [prepared[1]] }
    ]);
    expect(prepared[1].sports).toEqual(["padel", "tennis"]);
    expect(clubImportIdentityKey(rows[1])).toBe(clubImportIdentityKey(rows[2]));
    expect(clubImportIdentityKey(rows[1])).toBe("юг::тверская улица, 1::москва");
  });

  it("uses canonical source_external_id and keeps the legacy fallback", () => {
    const row = { city: "Санкт-Петербург", name: "Север", address: "Невский, 1" };

    expect(resolveClubImportSourceExternalId({ ...row, sourceExternalId: "yandex-org:123" })).toBe("yandex-org:123");
    expect(resolveClubImportSourceExternalId(row)).toBe("север::невский, 1::санкт-петербург");
  });

  it("deduplicates canonical category rows by explicit source id", () => {
    const base: TestClubRow = {
      city: "Санкт-Петербург",
      name: "Север",
      address: "Невский, 1",
      sports: ["tennis"],
      websiteUrl: null,
      sourceExternalId: "yandex-org:123"
    };
    const [merged] = mergeClubImportRows([
      base,
      { ...base, name: "Север — падел", sports: ["padel"] }
    ]);

    expect(merged.sports).toEqual(["tennis", "padel"]);
    expect(merged.name).toBe("Север — падел");
  });

  it("scopes seed manual-court retirement to Saint Petersburg only", () => {
    expect(saintPetersburgManualCourtsRetirementFilter()).toEqual({
      city: "Санкт-Петербург",
      sourceType: "manual"
    });
  });
});
