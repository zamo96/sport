import React, { createElement } from "react";
import { describe, expect, it, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { getPrivacyPolicyDocument } from "@/lib/legal";
import { getLegalDocumentRegistryEntry } from "@/server/legal-documents";
import { LegalDocumentPage } from "@/components/legal/legal-document-page";

vi.stubGlobal("React", React);

function strings(value: unknown): string[] {
  if (typeof value === "string") return [value];
  if (value && typeof value === "object") return Object.values(value).flatMap(strings);
  return [];
}

describe("public legal candidate", () => {
  it("includes all purposes and the privacy matrix in both languages", () => {
    for (const language of ["ru", "en"] as const) {
      const privacy = getPrivacyPolicyDocument(language);
      expect(privacy.sections).toHaveLength(10);
      const table = privacy.sections.flatMap((section) => section.table ? [section.table] : [])[0];
      expect(table.headers).toHaveLength(4);
      expect(table.rows).toHaveLength(10);
      expect(table.rows.every((row) => row.length === 4)).toBe(true);
    }
  });

  it("renders the privacy table contained in the immutable receipt", () => {
    const entry = getLegalDocumentRegistryEntry("privacy", "ru");
    const html = renderToStaticMarkup(createElement(LegalDocumentPage, { document: entry }));
    expect(html).toContain("<table");
    expect(html).toContain("Фотографии");
    expect(html).toContain("ЯНДЕКС.ОБЛАКО");
    expect(entry.snapshot.sections).toEqual(entry.sections);
  });

  it("renders the historical privacy text without inventing unavailable language or dates", () => {
    const entry = getLegalDocumentRegistryEntry("privacy", "ru", "2026-09-24");
    const html = renderToStaticMarkup(createElement(LegalDocumentPage, { document: entry }));
    expect(html).toContain(entry.title);
    expect(html).not.toContain("English");
    if (!entry.effectiveDate) expect(html).not.toContain("Дата редакции:");
    expect(entry.snapshot.sections).toEqual(entry.sections);
  });

  it("describes VK ID sign-in and sliding sessions in the 2026-10-07 privacy policy", () => {
    const ru = getLegalDocumentRegistryEntry("privacy", "ru");
    const en = getLegalDocumentRegistryEntry("privacy", "en");
    expect(ru.version).toBe("2026-10-07");
    expect(ru.effectiveDate).toBe("7 октября 2026 года");
    expect(en.effectiveDate).toBe("October 7, 2026");
    const ruText = strings(ru.snapshot).join(" ");
    const enText = strings(en.snapshot).join(" ");
    expect(ruText).toContain("VK ID ООО «ВК»");
    expect(ruText).toContain("сеанс — 180 дней с последней активности");
    expect(ruText).not.toContain("сеанс — 14 дней");
    expect(enText).toContain("VK ID service of VK LLC");
    expect(enText).toContain("sessions 180 days from the last activity");
  });

  it("serves the 2026-10-05 privacy policy exactly as it was published", () => {
    // Hashes of the revision live from 2026-10-05 until the 2026-10-07 edition.
    expect(getLegalDocumentRegistryEntry("privacy", "ru", "2026-10-05").hash).toBe("a3cc280503293d0309db30d05545f5897620a287f5a89f33cd51643930632a19");
    expect(getLegalDocumentRegistryEntry("privacy", "en", "2026-10-05").hash).toBe("194be92bc55f1931d85d13a47e09fb8298747a061d73fd8f687796ca3c4df4ac");
    expect(getLegalDocumentRegistryEntry("privacy", "ru", "2026-10-05").effectiveDate).toBe("5 октября 2026 года");
    expect(() => getLegalDocumentRegistryEntry("privacy", "ru", "2026-10-06")).toThrow("LEGAL_DOCUMENT_VERSION_NOT_FOUND");
  });

  it("includes the mandatory Russian explanation on the separate public recommendation page", () => {
    const entry = getLegalDocumentRegistryEntry("recommendations", "ru");
    const html = renderToStaticMarkup(createElement(LegalDocumentPage, { document: entry }));
    expect(html).toContain("На информационном ресурсе при применении информационных технологий предоставления информации осуществляется сбор, систематизация и анализ сведений, относящихся к предпочтениям пользователей сети «Интернет», находящихся на территории Российской Федерации.");
  });

  it("has no drafting placeholders, obsolete legacy exception or current payment offer", () => {
    for (const key of ["terms", "privacy", "profile-visibility", "analytics", "recommendations"] as const) {
      for (const language of ["ru", "en"] as const) {
        const entry = getLegalDocumentRegistryEntry(key, language);
        const text = strings(entry.snapshot).join(" ");
        expect(text).not.toMatch(/\[\[|Рабочая редакция|Редакторская справка|TODO|показываются как прежде/);
        expect(entry.url).toContain(`/${entry.version}?lang=${language}&hash=${entry.hash}`);
      }
    }
  });
});
