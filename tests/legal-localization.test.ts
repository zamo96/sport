import { describe, expect, it } from "vitest";

import {
  getUserAgreementDocument,
  resolveLegalLanguage,
  USER_AGREEMENT_DOCUMENTS,
  USER_AGREEMENT_SECTIONS,
  USER_AGREEMENT_SECTIONS_EN,
  USER_AGREEMENT_VERSION
} from "@/lib/legal";

function agreementText(language: "ru" | "en") {
  return USER_AGREEMENT_DOCUMENTS[language].sections
    .flatMap((section) => [section.title, ...(section.paragraphs ?? []), ...(section.bullets ?? [])])
    .join(" ");
}

describe("user agreement localization", () => {
  it("defaults missing, invalid, and multi-value language parameters to Russian", () => {
    expect(resolveLegalLanguage(undefined)).toBe("ru");
    expect(resolveLegalLanguage("de")).toBe("ru");
    expect(resolveLegalLanguage(["en"])).toBe("ru");
    expect(getUserAgreementDocument(undefined)).toBe(USER_AGREEMENT_DOCUMENTS.ru);
    expect(getUserAgreementDocument("invalid")).toBe(USER_AGREEMENT_DOCUMENTS.ru);
    expect(getUserAgreementDocument("en")).toBe(USER_AGREEMENT_DOCUMENTS.en);
  });

  it("keeps the complete 17-section structure in both languages", () => {
    expect(USER_AGREEMENT_SECTIONS).toHaveLength(17);
    expect(USER_AGREEMENT_SECTIONS_EN).toHaveLength(17);
    expect(USER_AGREEMENT_SECTIONS_EN).toHaveLength(USER_AGREEMENT_SECTIONS.length);
  });

  it("uses the same legal version for both languages", () => {
    expect(USER_AGREEMENT_DOCUMENTS.ru.version).toBe(USER_AGREEMENT_VERSION);
    expect(USER_AGREEMENT_DOCUMENTS.en.version).toBe(USER_AGREEMENT_VERSION);
  });

  it("retains every required UGC safety commitment in English", () => {
    const text = agreementText("en");

    expect(text).toMatch(/zero tolerance/i);
    expect(text).toMatch(/report another User/i);
    expect(text).toMatch(/block that User/i);
    expect(text).toMatch(/immediately removed from the blocking User's feed/i);
    expect(text).toMatch(/Operator is notified/i);
    expect(text).toMatch(/within 24 hours/i);
    expect(text).toMatch(/removes or hides the relevant Content/i);
    expect(text).toMatch(/ejects the offending User/i);
  });

  it("retains the corresponding UGC safety commitments in Russian", () => {
    const text = agreementText("ru");

    expect(text).toMatch(/нулевая терпимость/i);
    expect(text).toMatch(/пожаловаться/i);
    expect(text).toMatch(/заблокировать/i);
    expect(text).toMatch(/немедленно перестает показываться/i);
    expect(text).toMatch(/Оператор получает уведомление/i);
    expect(text).toMatch(/в течение 24 часов/i);
    expect(text).toMatch(/удаляет или скрывает/i);
    expect(text).toMatch(/прекращает доступ нарушившего Пользователя/i);
  });
});
