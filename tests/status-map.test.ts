import { describe, expect, it } from "vitest";

import {
  translateGameRequestStatus,
  translateGameSearchResponseStatus,
  translateGameSearchStatus,
  translateRegularPairOccurrenceStatus,
  translateRegularPairStatus
} from "@/lib/status-map";

describe("canonical status map", () => {
  it("translates game search statuses", () => {
    expect(translateGameSearchStatus("active")).toBe("Идет набор");
    expect(translateGameSearchStatus("in_review")).toBe("Ожидает решения");
    expect(translateGameSearchStatus("matched")).toBe("Игроки найдены");
    expect(translateGameSearchStatus("closed")).toBe("Закрыт");
  });

  it("translates game search response statuses", () => {
    expect(translateGameSearchResponseStatus("pending")).toBe("Ожидает");
    expect(translateGameSearchResponseStatus("approved")).toBe("Подтвержден");
    expect(translateGameSearchResponseStatus("rejected")).toBe("Отклонен");
    expect(translateGameSearchResponseStatus("rejected", { isSearchMatched: true })).toBe("Игрок найден");
    expect(translateGameSearchResponseStatus("withdrawn")).toBe("Отозван");
  });

  it("translates game request statuses with role awareness", () => {
    expect(translateGameRequestStatus("pending", { isCreator: true })).toBe("Ожидает подтверждения");
    expect(translateGameRequestStatus("pending", { isCreator: false })).toBe("Ждёт твоего решения");
    expect(translateGameRequestStatus("accepted")).toBe("Игра подтверждена");
    expect(translateGameRequestStatus("declined")).toBe("Отклонено");
    expect(translateGameRequestStatus("canceled")).toBe("Отменено");
  });

  it("translates regular play statuses", () => {
    expect(translateRegularPairStatus("active")).toBe("Активная пара");
    expect(translateRegularPairStatus("paused")).toBe("Пара на паузе");
    expect(translateRegularPairStatus("closed")).toBe("Пара закрыта");

    expect(translateRegularPairOccurrenceStatus("pending")).toBe("Ожидает подтверждения");
    expect(translateRegularPairOccurrenceStatus("confirmed")).toBe("Игра подтверждена");
    expect(translateRegularPairOccurrenceStatus("declined")).toBe("Отклонено");
    expect(translateRegularPairOccurrenceStatus("canceled")).toBe("Отменено");
    expect(translateRegularPairOccurrenceStatus("expired")).toBe("Истекло");
  });
});
