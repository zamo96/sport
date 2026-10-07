import { createHash } from "node:crypto";
import archivedTermsRu from "./legal-archive/terms-2026-09-24-ru.json";
import archivedTermsEn from "./legal-archive/terms-2026-09-24-en.json";
import archivedProfileRu from "./legal-archive/profile-visibility-2026-09-24-ru.json";
import archivedProfileEn from "./legal-archive/profile-visibility-2026-09-24-en.json";
import archivedAnalyticsRu from "./legal-archive/analytics-2026-09-24-ru.json";
import archivedAnalyticsEn from "./legal-archive/analytics-2026-09-24-en.json";
import archivedPrivacyRu from "./legal-archive/privacy-2026-09-24-ru.json";
import archivedPrivacy1005Ru from "./legal-archive/privacy-2026-10-05-ru.json";
import archivedPrivacy1005En from "./legal-archive/privacy-2026-10-05-en.json";
import { getConsentDocument } from "@/lib/legal-consents";
import { getUserAgreementDocument, getPrivacyPolicyDocument, getRecommendationsDocument, type LegalLanguage, type UserAgreementSection } from "@/lib/legal";
import { LEGAL_OPERATOR } from "@/lib/legal-contract";
export type ConsentDocumentMeta = { version: string; hash: string; language: LegalLanguage; url: string };

export type LegalDocumentKey = "terms" | "privacy" | "profile-visibility" | "analytics" | "recommendations";

/** Stable JSON serialization includes every displayed field, including tables. */
export function canonicalLegalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalLegalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.entries(value).filter(([, child]) => child !== undefined).sort(([a], [b]) => a.localeCompare(b))
      .map(([key, child]) => `${JSON.stringify(key)}:${canonicalLegalJson(child)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function getLegalDocumentRegistryEntry(key: LegalDocumentKey, language: LegalLanguage = "ru", version?: string) {
  const currentDocument = key === "terms" ? getUserAgreementDocument(language)
    : key === "privacy" ? getPrivacyPolicyDocument(language)
    : key === "recommendations" ? getRecommendationsDocument(language)
    : getConsentDocument(key, language);
  type ArchivedDocument = { language: string; title: string; description?: string; version: string; effectiveDate?: string;
    sections: UserAgreementSection[]; operator: typeof LEGAL_OPERATOR };
  // Earlier revisions, by document and version, exactly as they were served.
  const archives: Partial<Record<string, Partial<Record<LegalLanguage, ArchivedDocument>>>> = {
    "terms@2026-09-24": { ru: archivedTermsRu, en: archivedTermsEn },
    "profile-visibility@2026-09-24": { ru: archivedProfileRu, en: archivedProfileEn },
    "analytics@2026-09-24": { ru: archivedAnalyticsRu, en: archivedAnalyticsEn },
    "privacy@2026-09-24": { ru: archivedPrivacyRu },
    "privacy@2026-10-05": { ru: archivedPrivacy1005Ru, en: archivedPrivacy1005En }
  };
  const archived = version && version !== currentDocument.version ? archives[`${key}@${version}`]?.[language] : undefined;
  if (version && currentDocument.version !== version && !archived) throw new Error("LEGAL_DOCUMENT_VERSION_NOT_FOUND");
  const document = archived ?? currentDocument;
  const operator = archived ? archived.operator : LEGAL_OPERATOR;
  const snapshot = {
    key,
    version: document.version,
    language,
    title: document.title,
    description: document.description,
    effectiveDate: document.effectiveDate,
    operator,
    sections: document.sections
  };
  const hash = createHash("sha256").update(canonicalLegalJson(snapshot)).digest("hex");
  const url = `/legal/${key}/${encodeURIComponent(document.version)}?lang=${language}&hash=${hash}`;
  return { ...document, key, operator, hash, url, snapshot };
}

export function currentDocumentHashes(key: LegalDocumentKey) {
  return [getLegalDocumentRegistryEntry(key, "ru").hash, getLegalDocumentRegistryEntry(key, "en").hash];
}

export function getConsentDocuments(language: LegalLanguage = "ru"): { profileVisibility: ConsentDocumentMeta; analytics: ConsentDocumentMeta } {
  const metadata = (key: "profile-visibility" | "analytics") => {
    const entry = getLegalDocumentRegistryEntry(key, language);
    return { version: entry.version, hash: entry.hash, language, url: entry.url };
  };
  return { profileVisibility: metadata("profile-visibility"), analytics: metadata("analytics") };
}

export function requireShownLegalDocument(key: "profile-visibility" | "analytics", proof?: { version: string; hash: string; language: LegalLanguage }) {
  if (!proof) throw new LegalDocumentRefreshError();
  const entry = getLegalDocumentRegistryEntry(key, proof.language);
  if (entry.version !== proof.version || entry.hash !== proof.hash) throw new LegalDocumentRefreshError();
  return entry;
}

export class LegalDocumentRefreshError extends Error {
  readonly code = "LEGAL_DOCUMENT_REFRESH_REQUIRED";
  constructor() { super("Откройте актуальный текст согласия и подтвердите выбранные условия заново"); }
}
