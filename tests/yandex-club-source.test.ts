import { Sport } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";

import {
  buildPreparedYandexClubs,
  extractYandexOrganizationCoordinates,
  fetchYandexOrganizationCoordinates,
  groupRawYandexClubs,
  parseYandexOrganizationUrl,
  selectSourceUrl
} from "@/lib/yandex-club-source";

describe("Yandex clubs source preparation", () => {
  it("normalizes an organization URL and extracts only exact-id coordinates", () => {
    expect(parseYandexOrganizationUrl("https://yandex.ru/maps/org/club_name/123/reviews")).toEqual({
      orgId: "123",
      url: "https://yandex.ru/maps/org/club_name/123/"
    });
    const html = [
      '<div data-id="999" data-coordinates="30.1,59.1"></div>',
      '<div data-coordinates="30.25,59.95" data-id="123"></div>'
    ].join("");
    expect(extractYandexOrganizationCoordinates(html, "123")).toEqual({ lat: 59.95, lng: 30.25 });
    expect(extractYandexOrganizationCoordinates(html, "456")).toBeNull();
  });

  it("takes the first usable scalar URL and denies Yandex service links", () => {
    expect(selectSourceUrl("https://ya.ru/ | https://club.test/path | https://other.test")).toBe(
      "https://club.test/path"
    );
    expect(selectSourceUrl("https://t.me/mapsyandex | https://t.me/real_club")).toBe("https://t.me/real_club");
  });

  it("groups category duplicates by org id and unions sports", () => {
    const grouped = groupRawYandexClubs([
      {
        "Поисковый запрос": "Теннис Санкт-Петербург",
        "Название": "Спортцентр",
        "Адрес": "Невский, 1",
        "Телефон": "+7 900 000-00-00 | служебное",
        "Сайт": "https://sport.test | https://ya.ru/",
        "Ссылка на Яндекс Карты": "https://yandex.ru/maps/org/sport/123/gallery"
      },
      {
        "Поисковый запрос": "Падел Санкт-Петербург",
        "Название": "Спортцентр",
        "Адрес": "Невский, 1",
        "Telegram": "https://t.me/sport | https://t.me/mapsyandex",
        "Ссылка на Яндекс Карты": "https://yandex.ru/maps/org/sport/123/reviews"
      }
    ]);
    expect(grouped).toHaveLength(1);
    expect(grouped[0]).toMatchObject({
      orgId: "123",
      sports: [Sport.tennis, Sport.padel],
      phone: "+7 900 000-00-00",
      websiteUrl: "https://sport.test",
      telegramUrl: "https://t.me/sport"
    });
  });

  it("retries a rate limit, caches coordinates and builds canonical rows", async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response("rate limited", { status: 429, headers: { "retry-after": "0" } }))
      .mockResolvedValueOnce(
        new Response('<div data-id="123" data-coordinates="30.25,59.95"></div>', { status: 200 })
      );
    const source = {
      orgId: "123",
      yandexMapsUrl: "https://yandex.ru/maps/org/sport/123/",
      name: "Спортцентр",
      address: "Невский, 1",
      sports: [Sport.tennis],
      phone: null,
      websiteUrl: null,
      whatsappUrl: null,
      vkUrl: null,
      telegramUrl: "https://t.me/sport",
      maxUrl: null
    };
    const cacheDir = `/tmp/yandex-club-source-test-${process.pid}-${Date.now()}`;
    const coordinates = await fetchYandexOrganizationCoordinates([source], {
      cacheDir,
      fetchImpl,
      sleepImpl: async () => undefined
    });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(buildPreparedYandexClubs([source], coordinates)[0]).toMatchObject({
      source_external_id: "yandex-org:123",
      sports: [Sport.tennis],
      messenger_type: "telegram",
      lat: 59.95,
      lng: 30.25
    });
    await fetchYandexOrganizationCoordinates([source], { cacheDir, fetchImpl });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});
