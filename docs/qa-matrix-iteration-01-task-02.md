# QA Verification Matrix — Iteration 01 / Task 02

Последнее обновление: `2026-04-20 01:20:44 MSK`

## Что проверяем (фокус Task 02)

Ожидаемые изменения этой итерации затрагивают 4 блока — матрица построена вокруг них:

1. `onboarding` (Web + iOS): понятность шагов, корректные редиректы, сохранение/переиспользование черновика, email только в момент защищённого действия.
2. `player card reasons`: 2–4 понятные причины «почему этот игрок релевантен» + отсутствие вводящих в заблуждение причин.
3. `sport-specific defaults`: `format`, `playersNeeded`, `durationMinutes` и ограничения форматов зависят от спорта и устойчивы при переключениях.
4. `status labels`: UI-лейблы статусов согласованы с `canonical status map` и не расползаются между Web/iOS/бэкендом.

## Канонический контракт (source of truth)

### Status map (UI-лейблы)

Источник:

- Web/shared: `src/lib/status-map.ts`

Ожидаемые лейблы:

- `GameSearch.status`:
  - `active` → `Идет набор`
  - `in_review` → `Ожидает решения`
  - `matched` → `Игроки найдены`
  - `closed` → `Закрыт`
- `GameSearchResponse.status`:
  - `pending` → `ожидает`
  - `approved` → `подтвержден`
  - `rejected` → `отклонен` (или `игрок найден`, если поиск уже `matched`)
  - `withdrawn` → `отозван`
- `GameRequest.status` (в карточках игры):
  - `pending` → `Ожидает подтверждения` (creator) / `Ждёт твоего решения` (recipient)
  - `accepted` → `Игра подтверждена`
  - `declined` → `Отклонено`
  - `canceled` → `Отменено`

Что запрещено:

- UI не должен «придумывать» новые статусы домена; только переводит канонические enum-значения в лейблы.
- Любые новые/нестабильные тексты (например, «В процессе набора») должны быть явно согласованы и не конфликтовать с `status-map`.

### Sport playbook (sport-specific defaults)

Источник:

- Web/backend shared: `src/lib/sport-playbook.ts`
- iOS shared: `ios/TennisSearchIOS/Core/AppModels.swift` (эквивалентные defaults/ограничения)

Ключевые ожидания для smoke:

- `padel` → только `doubles`
- `table_tennis`/`squash` → только `singles`
- `football`/`volleyball` → только `doubles`
- дефолты `durationMinutes` и `playersNeeded` обновляются при смене спорта/формата

### Player card reasons (explainability)

Контракт данных уже предусматривает поле:

- API candidates: `explainabilityReasons: string[]` (в ответах discover/preview), по умолчанию `[]`

Ожидания отображения:

- показывать 2–4 reasons (если они есть), без дублей, в стабильном порядке.
- reasons не должны быть «ложными»: если нет данных про доступность/спорт/район — соответствующая причина не должна появляться.

## Автоматические проверки (должны быть зелёные)

- `npm run test`
- `npm run lint`
- `npm run build`

Примечание по iOS: `xcodebuild` может быть недоступен в окружении без полного Xcode — тогда фиксируем риск компиляции.

## Verification matrix

### A. Web — onboarding (авторизованный пользователь)

1. Редиректы:
   - пользователь `onboardingCompleted=false` открывает `/discover` → редирект на `/onboarding`.
   - пользователь `onboardingCompleted=true` открывает `/onboarding` → редирект на `/discover`.
2. Шаги онбординга (3 шага):
   - шаг 1: нельзя продолжить без `name>=2`, `age>=18`.
   - шаг 2: нельзя продолжить без выбора хотя бы одного спорта.
   - шаг 3: `Пропустить пока` завершает onboarding без availability; `Начать поиск` — с availability (если указана).
3. Завершение:
   - после submit/finish → переход на `/discover` без циклических редиректов.
4. Регрессии:
   - повторный заход на `/onboarding` после успешного завершения не показывает форму.
   - ошибки `PATCH /me` отображаются и не приводят к «тихому» переходу на `/discover`.

### B. Web — onboarding (guest / auth flow)

1. Intro → profile → availability:
   - черновик сохраняется и переживает refresh страницы (`guest draft`).
   - кнопка «Смотреть игроков» доступна только при заполненных базовых полях (имя/возраст/спорт).
2. Guest discover:
   - guest может открыть `/discover` и видеть карточки игроков.
   - guest свайп `dislike` работает без auth, `like` вызывает `AuthRequiredSheet` и сохраняет pending action.
3. Email:
   - запрос кода: `POST /auth/request-link` → переход на ввод кода.
   - verify: `POST /auth/verify` + последующий `PATCH /me` (если onboarding ещё не завершён) → переход на `continue`/`/discover`.
4. Регрессии:
   - guest не должен терять заполненный черновик при переходах `intro ↔ profile ↔ availability`.
   - неправильный код/ошибка сети не «ломает» состояние шага и показывает ошибку.

### C. iOS — onboarding (AuthView)

1. Intro → profile → availability:
   - `Начать` переводит на шаг profile; кнопка продолжения недоступна без базовых полей.
   - availability можно пропустить и всё равно открыть discover.
2. Persist:
   - `guestDraft` сохраняется в `AppModel` и используется для guest discover.
3. Email:
   - email спрашивается только в защищённых действиях (мэтчи/чаты/сохранения откликов).
4. Регрессии:
   - повторный заход в AuthView после авторизации не показывает onboarding снова.

### D. Player cards — reasons (Web + iOS)

Smoke-правила:

1. Web swipe-card:
   - reasons (если есть) видны в карточке и не ломают layout (переполнение/длинные строки).
   - reasons не должны конфликтовать с видимыми фактами (например, «рядом», когда `distanceLabel` далеко).
2. Web seeking/hot cards:
   - reasons привязаны к активному спорту (или к `latestSearch.sport`, если показывается карточка поиска).
3. iOS discover cards:
   - reasons отображаются аналогично Web (2–4 причины).

Негативные кейсы:

- если `explainabilityReasons=[]`, UI не показывает заглушки «почему подходит».
- если у игрока нет availability, причины, связанные со временем, отсутствуют.

### E. Sport-specific defaults — Web

#### Create Game Search

1. `Регулярный поиск`:
   - выбрать `tennis` → дефолт `format=singles`, `playersNeeded=1`
   - сменить формат на `doubles` → дефолт `playersNeeded=3`
2. `Горячий поиск`:
   - выбрать `squash`/`table_tennis` → дефолт `durationMinutes=60`
   - выбрать `tennis`/`football` → дефолт `durationMinutes=90`
3. Ограничения форматов:
   - выбрать `padel` → формат доступен только `doubles`
   - выбрать `football`/`volleyball` → формат доступен только `doubles`
4. Переключение спорта:
   - сменить спорт на такой, где текущий формат недопустим → формат авто-резолвится в дефолт спорта.

#### Create Open Search из proposal/чатов (если применимо)

- `padel` → `format=doubles`, `playersNeeded` дефолт `3`
- `football` → `playersNeeded` дефолт `9`

### F. Sport-specific defaults — iOS (SearchesView)

1. Форматы:
   - `padel` → только `doubles`
   - `squash`/`table_tennis` → только `singles`
2. Players needed:
   - `tennis` → stepper в диапазоне `1...8`
   - `football`/`volleyball` → stepper в диапазоне `1...12`
3. Hot duration:
   - `squash`/`table_tennis` → дефолт `60`
   - `tennis`/`football` → дефолт `90`

### G. API contract — validation и обратная совместимость

1. Валидация `sport + format`:
   - `POST /game-searches`: `sport=padel` + `format=singles` → 4xx с ошибкой по `format`
   - `POST /game-requests`: `sport=padel` + `format=singles` → 4xx с ошибкой по `format`
2. Discover candidates:
   - `/users/discover` и `/users/discover/guest` возвращают `explainabilityReasons` как массив (никогда `null/undefined`).
   - старые клиенты должны игнорировать новые поля (если добавляются) без падений.

### H. Status labels — Web/iOS consistency

1. Web:
   - списки поисков/откликов/игр показывают лейблы из `status-map`/`game-requests` без расхождений по смыслу.
   - в местах, где есть «lifecycle» тексты (например, «Скоро начнется»), они не должны подменять доменный статус и не должны противоречить ему.
2. iOS:
   - статусы в списках поиска/матчей/игр не расходятся с Web по основным смыслам (`идет набор`, `ожидает решения`, `игра подтверждена`, `закрыт/отменено`).

## Регрессии (быстрый чек-лист)

### Web

- Onboarding → Discover: нет бесконечных редиректов.
- Discover swipe/likes: `dislike` гостю доступен, `like` требует email.
- Create search → respond → schedule → confirmed game: основной flow не сломан (по минимуму: страница открывается, статусы читаемы, CTA ведут туда, куда обещают).
- Modals/sheets: закрытие/возврат не теряет введённые данные и не оставляет «подвисших» оверлеев.

### iOS

- AuthView → DiscoverView: guest поток работает без email.
- SearchesView: создание/редактирование поиска не допускает несовместимые `sport + format`.
- Matches/Chats: защищённые действия требуют email (если пользователь гость/не завершил onboarding).

## Риски / что может сломаться

- Если в iOS где-то ещё используется полный список форматов (`allCases`) без фильтра по спорту, API начнёт возвращать 4xx — это проявится как «не сохраняется поиск».
- Если reasons начнут приходить из backend/matching, но UI не умеет их безопасно рендерить, возможны layout-regressions (особенно на маленьких экранах).
- Без `xcodebuild` остаётся риск компиляционных проблем Swift-проекта, даже при корректном изменении исходников.
