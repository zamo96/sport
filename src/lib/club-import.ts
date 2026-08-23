import { inferDistrictFromCoordinates } from "@/lib/club-sync";
import { DEFAULT_CITY } from "@/lib/constants";

type ClubImportIdentityRow<TSport extends string = string> = {
  city: string;
  name: string;
  address: string;
  sports: TSport[];
  sourceExternalId?: string | null;
};

type ClubImportDistrictLocationRow = {
  district: string | null;
  lat: number;
  lng: number;
};

export type ClubImportCityGroup<TRow> = {
  city: string;
  rows: TRow[];
};

function normalizeIdentityPart(value: string) {
  return value.trim().replace(/\s+/g, " ").toLocaleLowerCase("ru-RU");
}

export function clubImportIdentityKey(row: Pick<ClubImportIdentityRow, "city" | "name" | "address">) {
  // Keep the historical xlsx-import identifier stable for existing courts.
  return [row.name, row.address, row.city].map(normalizeIdentityPart).join("::");
}

function clubImportDedupeKey(row: ClubImportIdentityRow) {
  const sourceExternalId = row.sourceExternalId?.trim();
  if (sourceExternalId) {
    return `external::${sourceExternalId.toLocaleLowerCase("ru-RU")}`;
  }

  return [row.city, row.name, row.address].map(normalizeIdentityPart).join("::");
}

export function resolveClubImportSourceExternalId(
  row: Pick<ClubImportIdentityRow, "city" | "name" | "address" | "sourceExternalId">
) {
  return row.sourceExternalId?.trim() || clubImportIdentityKey(row);
}

/** Scope guard used by seed after the canonical workbook import. */
export function saintPetersburgManualCourtsRetirementFilter() {
  return {
    city: DEFAULT_CITY,
    sourceType: "manual"
  } as const;
}

/**
 * Resolves coordinate-based districts before the importer creates Court rows.
 * This keeps clean databases FK-safe because sync uses the same inference.
 */
export function withInferredClubImportDistricts<TRow extends ClubImportDistrictLocationRow>(rows: readonly TRow[]): TRow[] {
  return rows.map((row) => ({
    ...row,
    district: row.district ?? inferDistrictFromCoordinates(row.lat, row.lng)
  }));
}

/**
 * Collapses repeated workbook rows for the same club while retaining every
 * declared sport. Non-sport fields preserve the previous importer contract:
 * the last row wins.
 */
export function mergeClubImportRows<TRow extends ClubImportIdentityRow>(rows: readonly TRow[]): TRow[] {
  const byIdentity = new Map<string, TRow>();

  for (const row of rows) {
    const key = clubImportDedupeKey(row);
    const previous = byIdentity.get(key);

    byIdentity.set(
      key,
      previous
        ? {
            ...row,
            sports: Array.from(new Set([...previous.sports, ...row.sports]))
          }
        : { ...row, sports: [...row.sports] }
    );
  }

  return Array.from(byIdentity.values());
}

export function groupClubImportRowsByCity<TRow extends { city: string }>(
  rows: readonly TRow[]
): ClubImportCityGroup<TRow>[] {
  const groups = new Map<string, ClubImportCityGroup<TRow>>();

  for (const row of rows) {
    const group = groups.get(row.city);
    if (group) {
      group.rows.push(row);
    } else {
      groups.set(row.city, { city: row.city, rows: [row] });
    }
  }

  return Array.from(groups.values());
}
