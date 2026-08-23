import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";

import { Sport } from "@prisma/client";

export const YANDEX_CLUB_CITY = "Санкт-Петербург";

export type RawYandexClubRow = {
  "Поисковый запрос"?: unknown;
  "Название"?: unknown;
  "Адрес"?: unknown;
  "Телефон"?: unknown;
  "Сайт"?: unknown;
  "WhatsApp"?: unknown;
  "VK"?: unknown;
  "Telegram"?: unknown;
  "Max"?: unknown;
  "Ссылка на Яндекс Карты"?: unknown;
};

export type PreparedYandexClub = {
  source_external_id: string;
  yandex_org_id: string;
  name: string;
  address: string;
  city: typeof YANDEX_CLUB_CITY;
  sports: Sport[];
  phone: string | null;
  website_url: string | null;
  whatsapp_url: string | null;
  vk_url: string | null;
  telegram_url: string | null;
  max_url: string | null;
  messenger_type: "telegram" | "whatsapp" | "max" | "vk" | null;
  messenger_url: string | null;
  yandex_maps_url: string;
  lat: number;
  lng: number;
};

export type YandexOrganizationSource = {
  orgId: string;
  yandexMapsUrl: string;
  name: string;
  address: string;
  sports: Sport[];
  phone: string | null;
  websiteUrl: string | null;
  whatsappUrl: string | null;
  vkUrl: string | null;
  telegramUrl: string | null;
  maxUrl: string | null;
};

export type YandexCoordinates = { lat: number; lng: number };

export type PrepareYandexCoordinatesOptions = {
  cacheDir: string;
  concurrency?: number;
  retries?: number;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
  sleepImpl?: (ms: number) => Promise<void>;
  onProgress?: (completed: number, total: number) => void;
};

type CachedCoordinates = YandexCoordinates & {
  orgId: string;
  yandexMapsUrl: string;
  fetchedAt: string;
};

const SEARCH_SPORTS: Array<[RegExp, Sport]> = [
  [/настольный\s+теннис/iu, Sport.table_tennis],
  [/падел/iu, Sport.padel],
  [/сквош/iu, Sport.squash],
  [/бадминтон/iu, Sport.badminton],
  [/волейбол/iu, Sport.volleyball],
  [/футбол/iu, Sport.football],
  [/(?:^|\s)теннис(?:\s|$)/iu, Sport.tennis],
  [/фитнес/iu, Sport.fitness],
  [/единоборств/iu, Sport.boxing]
];

const DENIED_URL_HOSTS = new Set([
  "ya.ru",
  "www.ya.ru",
  "yandex.ru",
  "www.yandex.ru",
  "maps.yandex.ru"
]);

const DENIED_SERVICE_URLS = new Set([
  "https://t.me/mapsyandex",
  "https://telegram.me/mapsyandex",
  "https://vk.com/yandex.maps",
  "https://vk.ru/yandex.maps"
]);

function text(value: unknown) {
  return typeof value === "string" || typeof value === "number" ? String(value).trim() : "";
}

export function splitSourceValues(value: unknown) {
  return text(value)
    .split("|")
    .map((part) => part.trim())
    .filter(Boolean);
}

export function selectSourceScalar(value: unknown) {
  return splitSourceValues(value)[0] ?? null;
}

export function selectSourceUrl(value: unknown) {
  for (const candidate of splitSourceValues(value)) {
    try {
      const url = new URL(candidate);
      const normalized = `${url.protocol}//${url.host}${url.pathname}`.replace(/\/$/, "").toLocaleLowerCase("ru-RU");
      if (!/^https?:$/.test(url.protocol) || DENIED_URL_HOSTS.has(url.hostname.toLocaleLowerCase("en-US"))) {
        continue;
      }
      if (DENIED_SERVICE_URLS.has(normalized)) {
        continue;
      }
      return candidate;
    } catch {
      continue;
    }
  }
  return null;
}

export function sportsFromSearchQuery(value: unknown) {
  const query = text(value);
  return SEARCH_SPORTS.flatMap(([pattern, sport]) => (pattern.test(query) ? [sport] : []));
}

export function parseYandexOrganizationUrl(value: unknown) {
  const source = text(value);
  const match = source.match(/^https?:\/\/(?:www\.)?yandex\.(?:ru|com|kz)\/maps(?:\/[^/]+)?\/org\/([^/?#]+)\/(\d+)/iu);
  if (!match) {
    return null;
  }
  return {
    orgId: match[2],
    url: `https://yandex.ru/maps/org/${match[1]}/${match[2]}/`
  };
}

export function extractYandexOrganizationCoordinates(html: string, orgId: string): YandexCoordinates | null {
  const tags = html.match(/<[^>]+>/gu) ?? [];
  for (const tag of tags) {
    const id = tag.match(/\bdata-id=(?:"([^"]+)"|'([^']+)')/iu)?.slice(1).find(Boolean);
    if (id !== orgId) {
      continue;
    }
    const coordinates = tag.match(
      /\bdata-coordinates=(?:"([+-]?\d+(?:\.\d+)?),([+-]?\d+(?:\.\d+)?)"|'([+-]?\d+(?:\.\d+)?),([+-]?\d+(?:\.\d+)?)')/iu
    );
    if (!coordinates) {
      continue;
    }
    const lng = Number(coordinates[1] ?? coordinates[3]);
    const lat = Number(coordinates[2] ?? coordinates[4]);
    if (Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
      return { lat, lng };
    }
  }
  return null;
}

export function groupRawYandexClubs(rows: readonly RawYandexClubRow[]) {
  const result = new Map<string, YandexOrganizationSource>();
  for (const row of rows) {
    const reference = parseYandexOrganizationUrl(row["Ссылка на Яндекс Карты"]);
    const name = selectSourceScalar(row["Название"]);
    const address = selectSourceScalar(row["Адрес"]);
    const sports = sportsFromSearchQuery(row["Поисковый запрос"]);
    if (!reference || !name || !address || sports.length === 0) {
      continue;
    }

    const incoming: YandexOrganizationSource = {
      orgId: reference.orgId,
      yandexMapsUrl: reference.url,
      name,
      address,
      sports,
      phone: selectSourceScalar(row["Телефон"]),
      websiteUrl: selectSourceUrl(row["Сайт"]),
      whatsappUrl: selectSourceUrl(row["WhatsApp"]),
      vkUrl: selectSourceUrl(row["VK"]),
      telegramUrl: selectSourceUrl(row["Telegram"]),
      maxUrl: selectSourceUrl(row["Max"])
    };
    const existing = result.get(reference.orgId);
    if (!existing) {
      result.set(reference.orgId, incoming);
      continue;
    }
    result.set(reference.orgId, {
      ...existing,
      sports: Array.from(new Set([...existing.sports, ...incoming.sports])),
      phone: existing.phone ?? incoming.phone,
      websiteUrl: existing.websiteUrl ?? incoming.websiteUrl,
      whatsappUrl: existing.whatsappUrl ?? incoming.whatsappUrl,
      vkUrl: existing.vkUrl ?? incoming.vkUrl,
      telegramUrl: existing.telegramUrl ?? incoming.telegramUrl,
      maxUrl: existing.maxUrl ?? incoming.maxUrl
    });
  }
  return Array.from(result.values());
}

export function buildPreparedYandexClubs(
  organizations: readonly YandexOrganizationSource[],
  coordinates: ReadonlyMap<string, YandexCoordinates>
): PreparedYandexClub[] {
  return organizations.map((organization) => {
    const location = coordinates.get(organization.orgId);
    if (!location) {
      throw new Error(`Нет координат для Yandex org ${organization.orgId}`);
    }
    const messenger = firstMessenger(organization);
    return {
      source_external_id: `yandex-org:${organization.orgId}`,
      yandex_org_id: organization.orgId,
      name: organization.name,
      address: organization.address,
      city: YANDEX_CLUB_CITY,
      sports: organization.sports,
      phone: organization.phone,
      website_url: organization.websiteUrl,
      whatsapp_url: organization.whatsappUrl,
      vk_url: organization.vkUrl,
      telegram_url: organization.telegramUrl,
      max_url: organization.maxUrl,
      messenger_type: messenger?.type ?? null,
      messenger_url: messenger?.url ?? null,
      yandex_maps_url: organization.yandexMapsUrl,
      lat: location.lat,
      lng: location.lng
    };
  });
}

function firstMessenger(organization: YandexOrganizationSource) {
  if (organization.telegramUrl) return { type: "telegram" as const, url: organization.telegramUrl };
  if (organization.whatsappUrl) return { type: "whatsapp" as const, url: organization.whatsappUrl };
  if (organization.maxUrl) return { type: "max" as const, url: organization.maxUrl };
  if (organization.vkUrl) return { type: "vk" as const, url: organization.vkUrl };
  return null;
}

export async function fetchYandexOrganizationCoordinates(
  organizations: readonly Pick<YandexOrganizationSource, "orgId" | "yandexMapsUrl">[],
  options: PrepareYandexCoordinatesOptions
) {
  const concurrency = Math.max(1, Math.min(8, options.concurrency ?? 4));
  const results = new Map<string, YandexCoordinates>();
  await mkdir(options.cacheDir, { recursive: true });
  let nextIndex = 0;
  let completed = 0;
  const worker = async () => {
    while (true) {
      const index = nextIndex++;
      const organization = organizations[index];
      if (!organization) return;
      const coordinates = await coordinatesForOrganization(organization, options);
      results.set(organization.orgId, coordinates);
      completed += 1;
      options.onProgress?.(completed, organizations.length);
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, organizations.length) }, worker));
  return results;
}

async function coordinatesForOrganization(
  organization: Pick<YandexOrganizationSource, "orgId" | "yandexMapsUrl">,
  options: PrepareYandexCoordinatesOptions
) {
  const cachePath = path.join(options.cacheDir, `${organization.orgId}.json`);
  try {
    const cached = JSON.parse(await readFile(cachePath, "utf8")) as Partial<CachedCoordinates>;
    if (
      cached.orgId === organization.orgId &&
      typeof cached.lat === "number" &&
      typeof cached.lng === "number"
    ) {
      return { lat: cached.lat, lng: cached.lng };
    }
  } catch {
    // A missing or malformed cache entry is safely refreshed.
  }

  const fetchImpl = options.fetchImpl ?? fetch;
  const sleepImpl = options.sleepImpl ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  const retries = Math.max(0, options.retries ?? 3);
  let lastError: unknown;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 20_000);
    try {
      const response = await fetchImpl(organization.yandexMapsUrl, {
        redirect: "follow",
        signal: controller.signal,
        headers: {
          "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
          "accept-language": "ru-RU,ru;q=0.9"
        }
      });
      if (!response.ok) {
        const retryable = response.status === 429 || response.status >= 500;
        if (!retryable || attempt === retries) {
          throw new Error(`Yandex org ${organization.orgId}: HTTP ${response.status}`);
        }
        const retryAfter = retryAfterMs(response.headers.get("retry-after"));
        await sleepImpl(retryAfter ?? retryDelayMs(attempt));
        continue;
      }
      const html = await response.text();
      const coordinates = extractYandexOrganizationCoordinates(html, organization.orgId);
      if (!coordinates) {
        throw new Error(`Yandex org ${organization.orgId}: координаты не найдены в HTML`);
      }
      const cached: CachedCoordinates = {
        orgId: organization.orgId,
        yandexMapsUrl: organization.yandexMapsUrl,
        ...coordinates,
        fetchedAt: new Date().toISOString()
      };
      await atomicWriteJson(cachePath, cached);
      return coordinates;
    } catch (error) {
      lastError = error;
      if (attempt === retries || (error instanceof Error && error.message.includes("координаты не найдены"))) {
        break;
      }
      await sleepImpl(retryDelayMs(attempt));
    } finally {
      clearTimeout(timeout);
    }
  }
  throw lastError instanceof Error ? lastError : new Error(`Yandex org ${organization.orgId}: запрос не выполнен`);
}

function retryDelayMs(attempt: number) {
  const seconds = [2, 5, 15][Math.min(attempt, 2)];
  return seconds * 1000 + Math.floor(Math.random() * 500);
}

function retryAfterMs(value: string | null) {
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return seconds * 1000;
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(0, date - Date.now()) : null;
}

export async function atomicWriteJson(filePath: string, value: unknown) {
  await mkdir(path.dirname(filePath), { recursive: true });
  const temporaryPath = `${filePath}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  await rename(temporaryPath, filePath);
}
