import { fail, getErrorMessage } from "@/lib/http";

export function adminPlayersFailure(error: unknown) {
  const message = getErrorMessage(error);
  const errors: Record<string, [string, number]> = {
    ADMIN_UNCONFIGURED: ["Доступ администратора не настроен", 503],
    UNAUTHORIZED: ["Требуется авторизация", 401],
    FORBIDDEN: ["Недостаточно прав", 403],
    PLAYER_NOT_FOUND: ["Игрок не найден", 404],
    STALE_PLAYER_UPDATE: ["Профиль уже изменён. Обнови карточку и повтори попытку", 409],
    SELF_DEACTIVATION_FORBIDDEN: ["Нельзя деактивировать собственный аккаунт администратора", 403]
  };
  const mapped = errors[message];
  return mapped ? fail(mapped[0], mapped[1]) : fail(message);
}
