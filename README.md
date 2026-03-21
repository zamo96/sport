# MVP поиска теннисного партнера

Mobile-first PWA для быстрого поиска партнера по теннису, свайпов, мэтчей, чата и договоренности об игре на конкретном корте.

## Стек

- Next.js 14 + React + TypeScript
- Tailwind CSS
- PostgreSQL + Prisma
- Email OTP-аутентификация для MVP
- Гео-абстракция без жесткой привязки к провайдеру
- Яндекс Карты JS API v3 для отображения собственной базы спортивных центров
- Устанавливаемое PWA с offline-shell

## Что реализовано

- Вход по email + OTP через `POST /auth/request-link` и `POST /auth/verify`
- Онбординг и редактирование профиля через `GET /me` и `PATCH /me`
- Подбор игроков по расстоянию, уровню, формату, покрытию и пересечению по времени
- Быстрый deck с действиями `пропустить / можно поиграть`
- Автоматическое создание мэтча при взаимном лайке
- Список мэтчей и MVP-чат
- Список спортивных центров и карта через Яндекс Карты
- Создание предложения на игру и сценарий `принять / отклонить / отменить`
- Создание собственного поиска игры с днями и интервалами времени
- Список своих поисков, отклики и выбор одного или нескольких игроков для лобби
- Выбор района в Санкт-Петербурге и радиуса поиска по карте
- Доступность по каждому дню недели отдельно
- Блокировка пользователя и звуковой сигнал для новых сообщений/мэтчей
- Загрузка аватара в локальную папку `public/uploads`
- Сиды для полного демо-сценария
- Базовые тесты для scoring и переходов статусов заявки на игру

## Локальный запуск

1. Скопируй env-файл:

```bash
cp .env.example .env
```

2. Если хочешь включить карту через Яндекс, добавь в `.env`:

```bash
NEXT_PUBLIC_MAP_PROVIDER=yandex
NEXT_PUBLIC_YANDEX_MAPS_API_KEY=твой_ключ_яндекса
```

3. Подними весь локальный стек:

```bash
npm run dev:local
```

Команда:

- поднимет PostgreSQL в Docker
- сгенерирует Prisma Client
- применит схему
- загрузит сиды
- запустит Next.js dev server

Открой [http://localhost:3000](http://localhost:3000).

## Демо-сценарий

На экране авторизации можно использовать любую почту. В режиме разработки OTP показывается в интерфейсе и пишется в терминал.

Демо-пользователи:

- `anna@tennis.dev`
- `elena@tennis.dev`
- `maria@tennis.dev`
- `daria@tennis.dev`
- `sofia@tennis.dev`
- `nina@tennis.dev`

Рекомендуемый путь проверки:

1. Войди как новый пользователь или используй `anna@tennis.dev`
2. Заполни профиль
3. Открой поиск и пролистай карточки
4. Перейди в мэтчи
5. Зайди в чат
6. Отправь предложение на игру или создай собственный поиск

## Скрипты

- `npm run dev` - только Next.js dev server
- `npm run dev:local` - полный локальный стек MVP
- `npm run db:start` - только PostgreSQL
- `npm run db:setup` - Prisma generate + db push + seed
- `npm run build` - production-сборка
- `npm run lint` - ESLint
- `npm run test` - Vitest

## API

- `POST /auth/request-link`
- `POST /auth/verify`
- `GET /me`
- `PATCH /me`
- `GET /users/discover`
- `POST /swipes`
- `GET /matches`
- `GET /matches/:id/messages`
- `POST /matches/:id/messages`
- `GET /courts`
- `GET /courts/:id`
- `POST /game-requests`
- `PATCH /game-requests/:id`
- `GET /game-requests/my`
- `POST /game-searches`
- `GET /game-searches/my`
- `PATCH /game-searches/:id`
- `POST /game-searches/:id/respond`
- `PATCH /game-search-responses/:id`

## Архитектура

- UI-маршруты лежат в `/discover`, `/inbox`, `/play/courts`, `/play/proposals/new`, `/play/searches`, `/profile`, `/settings`
- API-эндпоинты повторяют требуемые маршруты, а UI-пути вынесены отдельно там, где иначе были бы коллизии
- Логика мэтчинга и ранжирования изолирована в `src/server` и `src/lib/scoring.ts`
- Гео-провайдер абстрагирован в `src/lib/geo.ts`
- Провайдер карты абстрагирован в `src/lib/maps`
- Auth намеренно упрощен для MVP и готов к замене на реальную email-доставку или внешний auth-провайдер

## Что осталось до production

- Реальная email-доставка и rate limiting для OTP
- Push-уведомления и background sync
- Админка или импортёр для пополнения собственной базы спортивных центров
- Реальные push-уведомления, системные разрешения и background sync
- Object storage для аватаров вместо локальной файловой системы
- Синхронизация бронирования с партнерами-кортами
- Жалобы, модерация, баны и antifraud
- Аналитика, observability и audit logs
- End-to-end тесты и нагрузочное тестирование
- Платежи и подписка
