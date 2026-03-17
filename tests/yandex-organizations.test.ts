import { describe, expect, it } from "vitest";

import { buildYandexOrganizationQuery } from "@/lib/maps/yandex-organizations";

describe("buildYandexOrganizationQuery", () => {
  it("uses explicit tennis club query for saint petersburg", () => {
    expect(buildYandexOrganizationQuery("Санкт-Петербург", "tennis")).toBe("Санкт-Петербург Теннисный клуб");
  });
});
