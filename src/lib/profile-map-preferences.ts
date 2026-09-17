import type { DistrictOption } from "@/lib/constants";

/** Keep an explicit empty choice empty; a legacy primary district is not consent.
 * Preserve invalid selections for server validation rather than silently broadening
 * them to whole-city visibility. The form offers an explicit clear action.
 */
export function normalizeProfilePreferredDistricts(value: unknown): DistrictOption[] {
  if (value == null) return [];
  if (!Array.isArray(value)) return [String(value) as DistrictOption];
  return Array.from(new Set(value.map((district) => String(district)))) as DistrictOption[];
}
