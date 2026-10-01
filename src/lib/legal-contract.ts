/** Редакция со входом по SMS и VK ID и реквизитами оператора как ИП. */
export const USER_AGREEMENT_VERSION = "2026-10-01";
/**
 * Первая редакция без встроенного согласия на обработку данных. Её шлют сборки
 * iOS и Android, выпущенные до 2026-10-01: при входе и на экране согласий.
 */
// TODO(rollout): remove after every supported iOS/Android build uses USER_AGREEMENT_VERSION.
export const SEPTEMBER_USER_AGREEMENT_VERSION = "2026-09-24";
// TODO(rollout): remove after every supported iOS/Android build uses USER_AGREEMENT_VERSION.
export const PREVIOUS_USER_AGREEMENT_VERSION = "2026-08-24";
// TODO(rollout): remove after every supported iOS build uses USER_AGREEMENT_VERSION.
export const LEGACY_USER_AGREEMENT_VERSION = "2026-07-05";
export const ACCEPTED_USER_AGREEMENT_VERSIONS = [
  USER_AGREEMENT_VERSION,
  SEPTEMBER_USER_AGREEMENT_VERSION,
  PREVIOUS_USER_AGREEMENT_VERSION,
  LEGACY_USER_AGREEMENT_VERSION
] as const;
/**
 * Редакции, в которых галочка соглашения одновременно означала согласие на
 * обработку данных. Для них в журнале по-прежнему пишется версия согласия,
 * чтобы запись отражала то, что человек реально видел на экране.
 */
const BUNDLED_CONSENT_AGREEMENT_VERSIONS: readonly string[] = [PREVIOUS_USER_AGREEMENT_VERSION, LEGACY_USER_AGREEMENT_VERSION];
export const USER_AGREEMENT_KEY = "user_agreement";
export const USER_AGREEMENT_EFFECTIVE_DATE = "1 октября 2026 года";
export const USER_AGREEMENT_TITLE = "Пользовательское соглашение НаТреню";
export const LEGAL_ACCEPTANCE_ERROR = "Нужно принять пользовательское соглашение";

/** Версии текстов отдельных согласий. Меняются вместе с текстом в `legal-consents.ts`. */
export const PROFILE_VISIBILITY_CONSENT_VERSION = "2026-09-24";
export const ANALYTICS_CONSENT_VERSION = "2026-09-24";

export type LegalAcceptanceSource = "email_otp" | "phone_otp" | "vk" | "apple" | "google";
export type AcceptedUserAgreementVersion = (typeof ACCEPTED_USER_AGREEMENT_VERSIONS)[number];

export type LatestUserAgreementPayload = {
  accepted: true;
  version: typeof USER_AGREEMENT_VERSION;
};

export const LEGAL_OPERATOR = {
  serviceName: "НаТреню",
  legalName: "Захаров Матвей Владимирович",
  inn: "ИНН: 471803649801",
  // Consent texts name the operator by `legalName` and INN: the same person before
  // and after registering as an individual entrepreneur, so consents stay valid.
  entrepreneurName: "индивидуальный предприниматель Захаров Матвей Владимирович",
  ogrnip: "ОГРНИП: 326470400131678",
  address: "187420, Россия, г. Сясьстрой, ул. Космонавтов, д. 8, кв. 15",
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
    personalDataConsentVersion: BUNDLED_CONSENT_AGREEMENT_VERSIONS.includes(agreementVersion) ? agreementVersion : null,
    acceptedVia: source,
    acceptedAt,
    ipAddress: ip ?? null,
    userAgent: userAgent ?? null
  };
}
