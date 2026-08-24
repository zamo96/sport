export const USER_AGREEMENT_VERSION = "2026-08-24";
// TODO(rollout): remove after every supported iOS build uses USER_AGREEMENT_VERSION.
export const LEGACY_USER_AGREEMENT_VERSION = "2026-07-05";
export const ACCEPTED_USER_AGREEMENT_VERSIONS = [USER_AGREEMENT_VERSION, LEGACY_USER_AGREEMENT_VERSION] as const;
export const USER_AGREEMENT_KEY = "user_agreement";
export const PERSONAL_DATA_CONSENT_VERSION = USER_AGREEMENT_VERSION;
export const USER_AGREEMENT_EFFECTIVE_DATE = "24 августа 2026 года";
export const USER_AGREEMENT_TITLE = "Пользовательское соглашение SportSearch";
export const LEGAL_ACCEPTANCE_ERROR = "Нужно принять пользовательское соглашение и дать согласие на обработку персональных данных";

export type LegalAcceptanceSource = "email_otp" | "apple";
export type AcceptedUserAgreementVersion = (typeof ACCEPTED_USER_AGREEMENT_VERSIONS)[number];

export type LatestUserAgreementPayload = {
  accepted: true;
  version: typeof USER_AGREEMENT_VERSION;
};

export const LEGAL_OPERATOR = {
  serviceName: "SportSearch",
  legalName: "Захаров Матвей Владимирович",
  inn: "ИНН: 471803649801",
  ogrn: "",
  address: "",
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
  agreementVersion,
  acceptedAt = new Date(),
  ip,
  userAgent
}: {
  userId: string;
  source: LegalAcceptanceSource;
  agreementVersion: AcceptedUserAgreementVersion;
  acceptedAt?: Date;
  ip?: string | null;
  userAgent?: string | null;
}) {
  return {
    userId,
    agreementKey: USER_AGREEMENT_KEY,
    agreementVersion,
    personalDataConsentVersion: agreementVersion,
    acceptedVia: source,
    acceptedAt,
    ipAddress: ip ?? null,
    userAgent: userAgent ?? null
  };
}
