import { describe, expect, it } from "vitest";

import { buildYandexOrganizationQuery } from "@/lib/maps/yandex-organizations";

describe("buildYandexOrganizationQuery", () => {
  it("uses explicit tennis club query for saint petersburg", () => {
    expect(buildYandexOrganizationQuery("Санкт-Петербург", "tennis")).toBe("Санкт-Петербург Теннисный клуб");
  });

  it("builds smart query from custom text and sport context", () => {
    expect(buildYandexOrganizationQuery("Санкт-Петербург", "tennis", "у метро")).toBe(
      "Санкт-Петербург Теннисный клуб у метро"
    );
    expect(buildYandexOrganizationQuery("Санкт-Петербург", "tennis", "Теннисный клуб у метро")).toBe(
      "Санкт-Петербург Теннисный клуб у метро"
    );
  });
});
