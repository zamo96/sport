import tzLookup from "tz-lookup";

export const DEFAULT_TIMEZONE = "Europe/Moscow";

function isUsableTimezone(zone: string) {
  try {
    new Intl.DateTimeFormat("en-GB", { timeZone: zone }).format(new Date());
    return true;
  } catch {
    return false;
  }
}

/**
 * Оффлайн-резолв IANA-зоны по координатам. Нужен именно географический поиск,
 * а не отображение страны в зону: у России и США по десятку зон на страну.
 */
export function resolveTimezoneFromCoordinates(
  latitude: number | null | undefined,
  longitude: number | null | undefined
): string | null {
  if (
    latitude == null ||
    longitude == null ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    Math.abs(latitude) > 90 ||
    Math.abs(longitude) > 180
  ) {
    return null;
  }

  try {
    const zone = tzLookup(latitude, longitude);
    return zone && isUsableTimezone(zone) ? zone : null;
  } catch {
    return null;
  }
}

export function resolveTimezoneOrDefault(
  latitude: number | null | undefined,
  longitude: number | null | undefined
) {
  return resolveTimezoneFromCoordinates(latitude, longitude) ?? DEFAULT_TIMEZONE;
}

/** Локальный час игрока (0–23) с откатом на зону по умолчанию. */
export function resolveLocalHour(timezone: string | null | undefined, now = new Date()) {
  return Number(getLocalDateParts(timezone, now).hour);
}

export function getLocalDateParts(timezone: string | null | undefined, now = new Date()) {
  const zone = timezone?.trim() || DEFAULT_TIMEZONE;
  const parts = formatParts(isUsableTimezone(zone) ? zone : DEFAULT_TIMEZONE, now);

  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour) % 24,
    dateKey: `${parts.year}-${parts.month}-${parts.day}`
  };
}

function formatParts(zone: string, now: Date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    // hour12:false здесь ставить нельзя: он перебивает hourCycle и возвращает
    // "24" вместо "00" в полночь.
    hourCycle: "h23"
  })
    .formatToParts(now)
    .reduce<Record<string, string>>((acc, part) => {
      if (part.type !== "literal") {
        acc[part.type] = part.value;
      }
      return acc;
    }, {});
}

/**
 * Момент, в который в зоне `timezone` наступает указанный локальный час
 * указанной локальной даты. Смещение берётся из самой зоны, поэтому переход на
 * летнее время учитывается автоматически.
 */
export function localDateTimeToUtc(
  timezone: string | null | undefined,
  year: number,
  month: number,
  day: number,
  hour: number
) {
  const zone = timezone?.trim() && isUsableTimezone(timezone.trim()) ? timezone.trim() : DEFAULT_TIMEZONE;
  const naive = Date.UTC(year, month - 1, day, hour, 0, 0, 0);
  let result = naive;

  // Две итерации: первая снимает основное смещение, вторая правит случай, когда
  // граница попала внутрь перевода часов.
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const parts = formatParts(zone, new Date(result));
    const asUtc = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour) % 24,
      Number(parts.minute),
      0,
      0
    );
    const offset = asUtc - result;
    result = naive - offset;
  }

  return new Date(result);
}
