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
