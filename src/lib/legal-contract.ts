export const USER_AGREEMENT_VERSION = "2026-07-05";
export const USER_AGREEMENT_KEY = "user_agreement";
export const PERSONAL_DATA_CONSENT_VERSION = USER_AGREEMENT_VERSION;
export const USER_AGREEMENT_EFFECTIVE_DATE = "5 июля 2026 года";
export const USER_AGREEMENT_TITLE = "Пользовательское соглашение TennisSearch";
export const LEGAL_ACCEPTANCE_ERROR = "Нужно принять пользовательское соглашение и дать согласие на обработку персональных данных";

export type LegalAcceptanceSource = "email_otp" | "apple";

export type LatestUserAgreementPayload = {
  accepted: true;
  version: typeof USER_AGREEMENT_VERSION;
};

export const LEGAL_OPERATOR = {
  serviceName: "TennisSearch",
  legalName: "Оператор сервиса TennisSearch (укажите юридическое лицо или ИП)",
  inn: "ИНН: укажите перед публикацией",
  ogrn: "ОГРН/ОГРНИП: укажите перед публикацией",
  address: "Адрес: укажите перед публикацией",
  email: "support@sportsearch.shop"
};

export function buildLatestUserAgreementPayload(): LatestUserAgreementPayload {
  return {
    accepted: true,
    version: USER_AGREEMENT_VERSION
  };
}

export function buildUserAgreementAcceptanceRecord({
  userId,
  source,
  acceptedAt = new Date(),
  ip,
  userAgent
}: {
  userId: string;
  source: LegalAcceptanceSource;
  acceptedAt?: Date;
  ip?: string | null;
  userAgent?: string | null;
}) {
  return {
    userId,
    agreementKey: USER_AGREEMENT_KEY,
    agreementVersion: USER_AGREEMENT_VERSION,
    personalDataConsentVersion: PERSONAL_DATA_CONSENT_VERSION,
    acceptedVia: source,
    acceptedAt,
    ipAddress: ip ?? null,
    userAgent: userAgent ?? null
  };
}
