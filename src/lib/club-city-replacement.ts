import { normalizeClubAddressIdentity, normalizeClubIdentityText } from "@/lib/club-sync";

export const SAINT_PETERSBURG_CITY = "Санкт-Петербург";

type ExistingCourt = {
  id: string;
  name: string;
  address: string;
  sourceExternalId?: string | null;
  normalizedName?: string | null;
  normalizedAddress?: string | null;
};

type IncomingClub = {
  name: string;
  address: string;
  sourceExternalId: string;
};

export type CityClubReplacementPlan = {
  matches: Array<{ courtId: string; incomingIndex: number }>;
  createIndexes: number[];
  retireCourtIds: string[];
};

export function assertAllowedClubReplacementCity(city: string) {
  if (city !== SAINT_PETERSBURG_CITY) {
    throw new Error(`Замена клубов разрешена только для города «${SAINT_PETERSBURG_CITY}»`);
  }
}

/**
 * Builds a conservative cutover plan. An id is retained only for a unique,
 * exact normalized name+address pair. Ambiguous identities are never guessed.
 */
export function buildCityClubReplacementPlan(
  existing: readonly ExistingCourt[],
  incoming: readonly IncomingClub[]
): CityClubReplacementPlan {
  const externalIds = new Set<string>();
  for (const row of incoming) {
    const externalId = row.sourceExternalId.trim();
    if (!externalId) {
      throw new Error("В replacement-наборе у каждого клуба должен быть source_external_id");
    }
    if (externalIds.has(externalId)) {
      throw new Error(`Дублирующийся source_external_id: ${externalId}`);
    }
    externalIds.add(externalId);
  }

  const existingByIdentity = groupIndexes(existing.map(existingIdentity));
  const incomingByIdentity = groupIndexes(incoming.map(incomingIdentity));
  const matchedCourtIds = new Set<string>();
  const matchedIncomingIndexes = new Set<number>();
  const matches: CityClubReplacementPlan["matches"] = [];

  // Once a canonical source id has been written, it is the authoritative and
  // idempotent identity. This phase also handles distinct clubs that happen to
  // share the same normalized name and address.
  const existingByExternalId = groupOptionalIndexes(existing.map((court) => court.sourceExternalId));
  const incomingByExternalId = groupOptionalIndexes(incoming.map((row) => row.sourceExternalId));
  for (const [externalId, incomingIndexes] of incomingByExternalId) {
    const existingIndexes = existingByExternalId.get(externalId) ?? [];
    if (incomingIndexes.length !== 1 || existingIndexes.length !== 1) {
      continue;
    }

    const incomingIndex = incomingIndexes[0];
    const courtId = existing[existingIndexes[0]].id;
    matches.push({ courtId, incomingIndex });
    matchedCourtIds.add(courtId);
    matchedIncomingIndexes.add(incomingIndex);
  }

  for (const [identity, incomingIndexes] of incomingByIdentity) {
    const unmatchedIncomingIndexes = incomingIndexes.filter((index) => !matchedIncomingIndexes.has(index));
    const existingIndexes = (existingByIdentity.get(identity) ?? []).filter(
      (index) => !matchedCourtIds.has(existing[index].id)
    );
    if (unmatchedIncomingIndexes.length !== 1 || existingIndexes.length !== 1) {
      continue;
    }

    const incomingIndex = unmatchedIncomingIndexes[0];
    const courtId = existing[existingIndexes[0]].id;
    matches.push({ courtId, incomingIndex });
    matchedCourtIds.add(courtId);
    matchedIncomingIndexes.add(incomingIndex);
  }

  return {
    matches,
    createIndexes: incoming.map((_, index) => index).filter((index) => !matchedIncomingIndexes.has(index)),
    retireCourtIds: existing.map((court) => court.id).filter((id) => !matchedCourtIds.has(id))
  };
}

function existingIdentity(court: ExistingCourt) {
  // Recompute from current display fields. Stored normalized fields may come
  // from an older normalization version and must not produce a false match.
  return identityKey(normalizeClubIdentityText(court.name), normalizeClubAddressIdentity(court.address));
}

function incomingIdentity(row: IncomingClub) {
  return identityKey(normalizeClubIdentityText(row.name), normalizeClubAddressIdentity(row.address));
}

function identityKey(name: string, address: string) {
  return `${name}::${address}`;
}

function groupIndexes(values: string[]) {
  const result = new Map<string, number[]>();
  values.forEach((value, index) => result.set(value, [...(result.get(value) ?? []), index]));
  return result;
}

function groupOptionalIndexes(values: Array<string | null | undefined>) {
  const result = new Map<string, number[]>();
  values.forEach((value, index) => {
    const normalized = value?.trim();
    if (normalized) {
      result.set(normalized, [...(result.get(normalized) ?? []), index]);
    }
  });
  return result;
}
