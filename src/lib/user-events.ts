export const USER_EVENT_TYPES = [
  "registration_completed",
  "profile_completed",
  "request_created",
  "request_accepted",
  "game_played",
  "message_sent",
  "app_open",
  "onboarding_step",
  "discover_view",
  "swipe",
  "search_created",
  "search_response",
  "match_created",
  "push_sent",
  "push_opened",
  "push_converted"
] as const;

export type UserEventType = (typeof USER_EVENT_TYPES)[number];

/**
 * Типы, которые клиент имеет право прислать сам. Всё остальное (push_sent,
 * push_converted, swipe, match_created) пишется только сервером, иначе метрики
 * можно подделать с устройства.
 */
export const CLIENT_REPORTABLE_EVENT_TYPES = [
  "app_open",
  "onboarding_step",
  "discover_view",
  "push_opened"
] as const satisfies readonly UserEventType[];

export type ClientReportableEventType = (typeof CLIENT_REPORTABLE_EVENT_TYPES)[number];

export function isClientReportableEventType(value: string): value is ClientReportableEventType {
  return (CLIENT_REPORTABLE_EVENT_TYPES as readonly string[]).includes(value);
}
