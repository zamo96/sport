import { describe, expect, it } from "vitest";

import { formatLocalDateTime } from "@/lib/timezone";

// 19:00 по Москве — это 16:00 UTC. Раньше сервер печатал именно 16:00,
// потому что forматировал в своей зоне.
const evening = new Date("2026-09-17T16:00:00.000Z");

describe("время в сообщениях", () => {
  it("печатает час, который выставил игрок, а не серверный", () => {
    expect(formatLocalDateTime("Europe/Moscow", evening)).toContain("19:00");
    expect(formatLocalDateTime("Europe/Moscow", evening)).not.toContain("16:00");
  });

  it("без зоны откатывается на Москву, а не на UTC", () => {
    expect(formatLocalDateTime(null, evening)).toContain("19:00");
    expect(formatLocalDateTime(undefined, evening)).toContain("19:00");
    expect(formatLocalDateTime("Not/AZone", evening)).toContain("19:00");
  });

  it("считает по календарю игрока", () => {
    expect(formatLocalDateTime("Asia/Novosibirsk", evening)).toContain("23:00");
    expect(formatLocalDateTime("Europe/London", evening)).toContain("17:00");
    // 16:00 UTC — в Новосибирске всё ещё 17 сентября, а в Москве уже 19:00 того же дня.
    expect(formatLocalDateTime("Asia/Novosibirsk", evening)).toContain("17.09");
  });

  it("переносит дату, когда локальные сутки уже сменились", () => {
    const lateNight = new Date("2026-09-17T21:30:00.000Z");
    expect(formatLocalDateTime("Europe/Moscow", lateNight)).toContain("18.09");
    expect(formatLocalDateTime("Europe/London", lateNight)).toContain("17.09");
  });
});
