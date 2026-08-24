import { fail, getErrorMessage } from "@/lib/http";

export function adminReportsFailure(error: unknown) {
  const message = getErrorMessage(error);
  const errors: Record<string, [string, number]> = {
    ADMIN_UNCONFIGURED: ["Доступ администратора не настроен", 503],
    UNAUTHORIZED: ["Требуется авторизация", 401],
    FORBIDDEN: ["Недостаточно прав", 403],
    CONTENT_REPORT_NOT_FOUND: ["Жалоба не найдена", 404],
    REPORTED_USER_NOT_FOUND: ["Пользователь уже удалён", 404],
    STALE_CONTENT_REPORT: ["Жалоба уже обработана или была изменена", 409],
    ADMIN_TARGET_DEACTIVATION_FORBIDDEN: ["Нельзя деактивировать аккаунт администратора по жалобе", 403]
  };
  const mapped = errors[message];
  return mapped ? fail(mapped[0], mapped[1]) : fail(message);
}
