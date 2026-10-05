import content from "@/lib/legal-release-content.json";
import { LEGAL_OPERATOR, USER_AGREEMENT_EFFECTIVE_DATE, USER_AGREEMENT_TITLE, USER_AGREEMENT_VERSION } from "@/lib/legal-contract";
export {
  ACCEPTED_USER_AGREEMENT_VERSIONS, LEGAL_ACCEPTANCE_ERROR, LEGACY_USER_AGREEMENT_VERSION,
  LEGAL_OPERATOR, PREVIOUS_USER_AGREEMENT_VERSION, USER_AGREEMENT_EFFECTIVE_DATE,
  USER_AGREEMENT_KEY, USER_AGREEMENT_TITLE, USER_AGREEMENT_VERSION,
  buildLatestUserAgreementPayload, buildUserAgreementAcceptanceRecord,
  type AcceptedUserAgreementVersion, type LatestUserAgreementPayload, type LegalAcceptanceSource
} from "@/lib/legal-contract";

export type UserAgreementSection = {
  title: string;
  paragraphs?: string[];
  bullets?: string[];
  table?: { headers: string[]; rows: string[][] };
};
export type LegalLanguage = "ru" | "en";
export type UserAgreementDocument = {
  language: LegalLanguage; title: string; description: string; version: string; effectiveDate: string;
  backLabel: string; versionLabel: string; effectiveDateLabel: string; operatorLabel: string;
  sections: UserAgreementSection[];
};
export const PRIVACY_POLICY_VERSION = "2026-10-05";
export const PRIVACY_POLICY_EFFECTIVE_DATE = "5 октября 2026 года";
export const PRIVACY_POLICY_TITLE = content.privacy.ru.title;
export const PRIVACY_POLICY_SERVICE_NAME = LEGAL_OPERATOR.serviceName;
export const RECOMMENDATIONS_VERSION = "2026-10-05";
export const USER_AGREEMENT_SECTIONS: UserAgreementSection[] = content.terms.ru.sections;
export const USER_AGREEMENT_SECTIONS_EN: UserAgreementSection[] = content.terms.en.sections;
export const PRIVACY_POLICY_SECTIONS: UserAgreementSection[] = content.privacy.ru.sections;
export const PRIVACY_POLICY_SECTIONS_EN: UserAgreementSection[] = content.privacy.en.sections;

function document(key: "terms" | "privacy" | "recommendations", language: LegalLanguage): UserAgreementDocument {
  const source = content[key][language];
  return {
    ...source, language,
    title: key === "terms" && language === "ru" ? USER_AGREEMENT_TITLE : source.title,
    version: key === "terms" ? USER_AGREEMENT_VERSION : key === "privacy" ? PRIVACY_POLICY_VERSION : RECOMMENDATIONS_VERSION,
    effectiveDate: language === "ru" ? USER_AGREEMENT_EFFECTIVE_DATE : "October 5, 2026",
    backLabel: language === "ru" ? "Назад" : "Back",
    versionLabel: language === "ru" ? "Редакция" : "Revision",
    effectiveDateLabel: language === "ru" ? "Дата редакции" : "Revision date",
    operatorLabel: language === "ru" ? "Оператор" : "Operator"
  };
}
export const USER_AGREEMENT_DOCUMENTS: Record<LegalLanguage, UserAgreementDocument> = { ru: document("terms", "ru"), en: document("terms", "en") };
export function resolveLegalLanguage(value: string | string[] | undefined): LegalLanguage { return value === "en" ? "en" : "ru"; }
export function getUserAgreementDocument(value: string | string[] | undefined): UserAgreementDocument { return USER_AGREEMENT_DOCUMENTS[resolveLegalLanguage(value)]; }
export function getPrivacyPolicyDocument(value: string | string[] | undefined): UserAgreementDocument { return document("privacy", resolveLegalLanguage(value)); }
export function getRecommendationsDocument(value: string | string[] | undefined): UserAgreementDocument { return document("recommendations", resolveLegalLanguage(value)); }
