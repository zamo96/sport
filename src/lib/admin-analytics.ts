export const ANALYTICS_PAGE_SIZE = 50;
export const ANALYTICS_EXPORT_LIMIT = 10000;
export const ANALYTICS_TIME_ZONE = "UTC";

export type AdminAnalyticsOptions = { days?: number; userId?: string; eventType?: string; page?: number };
export type AnalyticsFilters = { days: 7 | 30 | 90; userId: string; eventType: string; page: number };
export type AnalyticsJournalItem = {
  id: string; userId: string; userName: string | null; userEmail: string;
  type: string; label: string; entityType: string | null; entityId: string | null;
  context: unknown; createdAt: Date;
};
export type AnalyticsFunnelStep = {
  key: string; label: string; users: number; conversionFromPrevious: number | null;
  conversionFromRegistration: number | null; dropOff: number;
};
export type AdminAnalyticsData = {
  generatedAt: Date;
  filters: AnalyticsFilters;
  period: { from: Date; to: Date };
  coverage: { firstEventAt: Date | null; firstFunnelEventAt: Date | null; notes: string[] };
  metrics: {
    newUsers: number; activeUsers: number; totalEvents: number; playedUsers: number;
    playedGames: number; registrationToGameRate: number | null;
  };
  funnel: AnalyticsFunnelStep[];
  daily: Array<{ day: string; registrations: number; activeUsers: number; events: number; firstGames: number }>;
  eventBreakdown: Array<{ type: string; label: string; count: number; users: number }>;
  journal: { items: AnalyticsJournalItem[]; total: number; page: number; pageSize: number; totalPages: number };
};

const EVENT_LABELS: Record<string, string> = {
  app_open: "Открытие приложения", page_view: "Просмотр экрана", onboarding_step: "Шаг заполнения профиля",
  discover_view: "Просмотр поиска игроков", swipe: "Оценка игрока", search_created: "Создание поиска игры",
  search_response: "Отклик на поиск", match_created: "Взаимная симпатия", push_sent: "Отправка уведомления",
  push_opened: "Открытие уведомления", push_converted: "Действие после уведомления",
  registration_completed: "Регистрация", auth_login: "Вход в аккаунт", profile_completed: "Профиль заполнен",
  request_created: "Предложение игры", request_accepted: "Предложение принято", request_declined: "Предложение отклонено",
  request_canceled: "Игра отменена", game_played: "Игра отмечена сыгранной", game_outcome_updated: "Результат игры изменён",
  message_sent: "Сообщение отправлено", report_created: "Фотоотчёт добавлен", report_confirmation: "Статус фотоотчёта изменён"
};
export function analyticsEventLabel(type: string) { return EVENT_LABELS[type] ?? type; }
export function normalizeAnalyticsFilters(options: AdminAnalyticsOptions = {}): AnalyticsFilters {
  return {
    days: options.days === 7 || options.days === 90 ? options.days : 30,
    userId: (options.userId ?? "").trim().slice(0, 128),
    eventType: (options.eventType ?? "").trim().slice(0, 80),
    page: Number.isFinite(options.page) ? Math.max(1, Math.min(100000, Math.floor(options.page!))) : 1
  };
}
export function analyticsPeriod(days: number, now = new Date()) {
  const from = new Date(now);
  from.setUTCHours(0, 0, 0, 0);
  from.setUTCDate(from.getUTCDate() - days + 1);
  return { from, to: now };
}
export function analyticsRate(numerator: number, denominator: number) {
  return denominator > 0 ? Math.round(numerator / denominator * 1000) / 10 : null;
}
export function buildAnalyticsFunnel(counts: number[]): AnalyticsFunnelStep[] {
  const definitions = [
    ["registration", "Регистрация"], ["profile", "Профиль заполнен"],
    ["intent", "Первое действие для поиска игры"], ["accepted", "Игра согласована"],
    ["played", "Первая сыгранная игра (отмечена в приложении)"]
  ];
  return definitions.map(([key, label], index) => ({
    key, label, users: counts[index] ?? 0,
    conversionFromPrevious: index === 0 ? null : analyticsRate(counts[index] ?? 0, counts[index - 1] ?? 0),
    conversionFromRegistration: analyticsRate(counts[index] ?? 0, counts[0] ?? 0),
    dropOff: index === 0 ? 0 : Math.max(0, (counts[index - 1] ?? 0) - (counts[index] ?? 0))
  }));
}
export function escapeAnalyticsCsvCell(value: unknown) {
  const raw = value == null ? "" : String(value);
  // Spreadsheet apps interpret formulas even when CSV values are quoted.
  const safe = /^[\s\u0000-\u001f]*[=+@-]/u.test(raw) || /^[\t\r\n]/u.test(raw) ? `'${raw}` : raw;
  return `"${safe.replace(/"/g, '""')}"`;
}
export function analyticsJournalCsv(items: AnalyticsJournalItem[], truncated = false) {
  const rows: unknown[][] = [["created_at_utc", "event_id", "user_id", "user_name", "user_email", "event_type", "event_label", "entity_type", "entity_id", "context_json"]];
  for (const item of items) rows.push([
    item.createdAt.toISOString(), item.id, item.userId, item.userName, item.userEmail,
    item.type, item.label, item.entityType, item.entityId, item.context == null ? "" : JSON.stringify(item.context)
  ]);
  if (truncated) rows.push(["EXPORT_TRUNCATED", `Показаны последние ${ANALYTICS_EXPORT_LIMIT} событий. Сузьте период или фильтры.`]);
  return `\uFEFF${rows.map((row) => row.map(escapeAnalyticsCsvCell).join(",")).join("\r\n")}\r\n`;
}
