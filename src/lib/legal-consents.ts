import content from "@/lib/legal-release-content.json";
import { ANALYTICS_CONSENT_VERSION, PROFILE_VISIBILITY_CONSENT_VERSION, USER_AGREEMENT_EFFECTIVE_DATE } from "@/lib/legal-contract";
import type { LegalLanguage, UserAgreementSection } from "@/lib/legal";

export type ConsentDocumentKey = "profile-visibility" | "analytics";
export type ConsentDocument = {
  language: LegalLanguage; title: string; description: string; version: string;
  effectiveDate: string; versionLabel: string; operatorLabel: string;
  sections: UserAgreementSection[];
};
function document(key: ConsentDocumentKey, language: LegalLanguage): ConsentDocument {
  return {
    ...content[key][language], language,
    version: key === "profile-visibility" ? PROFILE_VISIBILITY_CONSENT_VERSION : ANALYTICS_CONSENT_VERSION,
    effectiveDate: language === "ru" ? USER_AGREEMENT_EFFECTIVE_DATE : "October 5, 2026",
    versionLabel: language === "ru" ? "Редакция" : "Revision",
    operatorLabel: language === "ru" ? "Оператор" : "Operator"
  };
}
export const CONSENT_DOCUMENTS: Record<ConsentDocumentKey, Record<LegalLanguage, ConsentDocument>> = {
  "profile-visibility": { ru: document("profile-visibility", "ru"), en: document("profile-visibility", "en") },
  analytics: { ru: document("analytics", "ru"), en: document("analytics", "en") }
};
export function getConsentDocument(key: ConsentDocumentKey, language: LegalLanguage): ConsentDocument { return CONSENT_DOCUMENTS[key][language]; }
