import { fail, getErrorMessage } from "@/lib/http";

export function adminClubsFailure(error: unknown) {
  const message = getErrorMessage(error);
  const errors: Record<string, [string, number]> = {
    ADMIN_UNCONFIGURED: ["Доступ администратора не настроен", 503],
    UNAUTHORIZED: ["Требуется авторизация", 401],
    FORBIDDEN: ["Недостаточно прав", 403],
    CLUB_NOT_FOUND: ["Клуб не найден", 404],
    STALE_CLUB_UPDATE: ["Клуб уже изменён. Обнови карточку и повтори попытку", 409],
    CLUB_CITY_INVALID: ["Город отсутствует в справочнике", 400],
    CLUB_DISTRICT_INVALID: ["Район не относится к выбранному городу", 400],
    CLUB_METRO_INVALID: ["Станция метро не относится к выбранному городу", 400],
    CLUB_SPORTS_REQUIRED: ["Для публикации укажи хотя бы один вид спорта", 400],
    CLUB_CITY_RELATIONS_REQUIRED: ["При смене города заново выбери или очисти район и метро", 400],
    CLUB_ARCHIVED_TRANSITION_INVALID: ["Архивный клуб сначала нужно перевести на проверку", 409],
    CLUB_PROFILE_INCOMPLETE: ["Для публикации заполни название, адрес, координаты и диапазон цен", 400]
  };
  const mapped = errors[message];
  return mapped ? fail(mapped[0], mapped[1]) : fail(message);
}
