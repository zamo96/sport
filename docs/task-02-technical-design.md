# Task 02 — Technical Design (Contract Freeze)

`Iteration 01 / Task 02 / Design Alignment For Onboarding, Player Cards, Modals And Sport-Specific Game Flow`

Дата фиксации: `2026-04-20` (ночной прогон).

Этот документ фиксирует технический контракт для explainability на `discover / player card` (2–4 причины релевантности), а также source of truth, затрагиваемые модули и порядок внедрения без конфликтов записи.

---

## 1) Контекст и цели

### Проблема

Карточка игрока в `discover` уже содержит данные и скоринг (`score`), но не объясняет *почему* этот игрок релевантен — из-за этого пользователю сложнее принять решение (лайк/пропуск, открыть детали, создать игру).

### Цель

Добавить в payload карточки 2–4 коротких причины, которые:

- **консистентны** между Web и iOS (одни и те же коды/смысл),
- **детерминированы** (стабильный порядок и правила выбора),
- **безопасны** (не раскрывают лишние персональные данные),
- **не меняют ranking** (объясняют уже существующие сигналы).

### Не цель (важно)

- Не менять формулу ранжирования в рамках explainability.
- Не добавлять новые доменные статусы (они фиксируются отдельно в `status map`).
- Не усложнять discover до “полного redesign”.

---

## 2) Контракт: payload для discover / player card

### Где используется

Единый preview-пayload пользователя используется:

- Web SSR: `src/server/app-data.ts` (`getDiscoverPageData` и списки),
- Web API: `GET /users/discover`, `POST /users/discover/guest`,
- iOS API client: те же endpoints (модель `DiscoverUser`).

### Изменение (additive)

В объект `DiscoverUser` (preview) добавляется поле:

```ts
type DiscoverUserPreview = {
  // существующие поля (примерно): id, name, age, city, districtLabel, distanceLabel, score, ...
  explainabilityReasons?: string[]; // 2–4 канонических коротких причины (RU)
};
```

Принципы:

- `explainabilityReasons` **опционально** (мягкий rollout, обратная совместимость).
- Клиенты **не вычисляют причины**: они отображают строки как есть (допустим fallback в UI, пока rollout не везде).

Примечание (upgrade path):

- При необходимости богатой UI-иконографии/метаданных можно ввести `explainabilityReasonsV2` как массив структур (`code/strength/meta`), но это **не блокирует** текущую продуктовую цель (сделать карточку объяснимой уже сейчас).

### Минимальный UI-контракт

- Web и iOS отображают **до 3 причин** в карточке (чипы/буллеты), но payload позволяет 4 (для деталей/листинга).
- Первые 2 причины считаются обязательными для “хорошего случая”; если данных недостаточно (нет координат/нет availability), допустимо вернуть меньше (см. fallback).

---

## 3) Правила выбора 2–4 причин (детерминизм)

### Входные сигналы (только существующие)

Explainability строится на уже существующих и/или дешево выводимых сигналах:

- спорт(ы) и пересечение (`preferredSports`, `sportLevels`)
- совместимость формата/покрытия (`preferredPlayFormat`, `preferredSurface`)
- дистанция / совпадение районов (`distanceKm`, `district/preferredDistricts` → уже используется в scoring)
- пересечение доступности (`availableDays`, `availableTimeRanges`)
- признак “ищет игру” (`isLookingForGame`)

Важно: причины **не должны** требовать новых запросов в БД и не должны зависеть от UI-only контекста.

### Нормативный порядок (для одинакового UI между платформами)

Причины сортируются и отбираются строго по следующему приоритету:

1. `actively_seeking` — если view=`hot` **или** `candidate.isLookingForGame === true` и это релевантно текущему view.
2. `shared_sport` — всегда, если кандидат попал в пул (shared sport уже соблюден).
3. `nearby` — если есть понятный сигнал близости (совпали районы **или** `distanceKm` известна и ≤ заданного порога).
4. `availability_overlap` — если есть пересечение по дням/временам (хотя бы 1).
5. `level_fit` — если уровень “достаточно близок” (gap ≤ 1 по хотя бы одному релевантному спорту).

Далее:

- Берём первые `max=4`.
- В “нормальном” swipe/likes view целимся в `2–3` причины; в seeking/hot допускается `3–4`.

### Политика strength

- `primary`: первые 1–2 причины.
- `secondary`: все остальные.

### Fallback (когда данных мало)

Если кандидат релевантен, но часть сигналов отсутствует, контракт допускает:

- вернуть только `shared_sport` + один из доступных (`actively_seeking` / `availability_overlap` / `level_fit`),
- если вообще нет дополнительных сигналов (редко) — вернуть только `shared_sport` (временно, пока не соберём минимум профиля в onboarding).

---

## 4) Source of truth и ownership

### Source of truth

Единый source of truth для вычисления `explainabilityReasons`:

- **shared helper в `src/lib`**, который работает одинаково для:
  - SSR (Web),
  - API routes,
  - guest discover.

Фактическая реализация v1 (ночной прогон):

- `src/lib/scoring.ts` остаётся источником `signals` (distance/overlap counts/level gap) и сортировки кандидатов.
- Helper: `buildDiscoverExplainabilityReasons(viewer, candidate, filters) => string[]`.

Почему так:

- чтобы не дублировать логику на клиентах,
- чтобы Matching Agent мог эволюционировать объясняемость без изменения UI-контрактов.

### Ownership (чтобы не было конфликтов записи)

- **Matching / Recommendation Agent**: правила выбора/тексты причин, helper в `src/lib`, тесты на детерминизм.
- **Backend Agent**: транспорт/сериализация (`src/server/serializers.ts` + routes), гарантия additive-контракта.
- **Frontend Agent**: отображение причин в Web карточках (без вычислений).
- **Mobile Agent**: отображение причин в iOS карточках (без вычислений).
- **QA Agent**: проверка, что причины есть, стабильны и не ломают flow.

---

## 5) Затрагиваемые модули (целевой список изменений)

> Код в этом документе не меняется; это карта затрагиваемых мест для реализации.

### Backend / Shared (TS)

- `src/lib/scoring.ts` — подключение explainability к `ScoredCandidate` (additive поле `explainabilityReasons`).
- `src/server/discover.ts` — получает кандидатов со скорингом (причины должны появиться “сами”).
- `src/server/serializers.ts` — `serializeUserPreview` пробрасывает `explainabilityReasons` (fallback `[]`).
- `src/app/users/discover/route.ts`, `src/app/users/discover/guest/route.ts` — контракт endpoints остаётся тем же, расширяется payload.

### Web UI

- `src/components/discover/swipe-deck.tsx` — показать 2–3 чипа причин рядом с метками спорта/формата.
- `src/components/discover/incoming-likes-list.tsx`, `src/components/discover/seeking-players-list.tsx` — аналогично.
- `src/components/discover/*sheet*` (если есть) — на detail view показать до 4 причин.

### iOS

- `ios/TennisSearchIOS/Core/AppModels.swift` — при необходимости расширить `DiscoverUser` (`explainabilityReasons: [String]`), но JSON decoding не должен ломаться и без этого.
- `ios/TennisSearchIOS/Views/DiscoverView.swift` (+ sheet) — отображение причин (чипы/буллеты).
- `ios/TennisSearchIOS/Services/MockRepository.swift` — обновить мок-данные (чтобы UI не пустовал в dev).

### Tests / QA

- `tests/explainability.test.ts` — детерминизм: порядок причин и границы длины.
- `docs/qa-matrix-iteration-01-task-02.md` — добавить проверки на reasons (см. ниже).

---

## 6) Порядок внедрения (без конфликтов записи)

### Шаг 0 — Contract freeze (этот документ)

- Фиксируем `DiscoverReasonCode`, payload `discoverReasons`, правила выбора и порядок.

### Шаг 1 — Shared explainability (Matching Agent)

- Добавить `src/lib/discover-explainability.ts`.
- Подключить его к `scoreCandidate(...)` так, чтобы `discoverReasons` появлялись на объекте кандидата.
- Добавить тест на детерминизм (2–4 причины, порядок, стабильность при равных входах).

**Конфликтов нет**: Matching работает в `src/lib/*` и `tests/*`.

### Шаг 2 — Transport (Backend Agent)

- Обновить `serializeUserPreview` для проброса `discoverReasons`.
- Убедиться, что `GET /users/discover` и `POST /users/discover/guest` возвращают расширенный payload.

**Конфликтов нет**: Backend работает в `src/server/*` и routes; не трогает UI.

### Шаг 3 — Web UI (Frontend Agent)

- Отрендерить причины в `player card` (swipe + likes + seeking/hot) без новых вычислений.
- Держать UI resilient: если `discoverReasons` нет, ничего не показывать.

**Конфликтов нет**: Frontend работает в `src/components/*`.

### Шаг 4 — iOS UI (Mobile Agent)

- Добавить модели и отрисовку причин.
- Обновить `MockRepository` для UI в offline/dev.

**Конфликтов нет**: Mobile работает в `ios/*`.

### Шаг 5 — QA (QA Agent)

Минимальный набор ручных проверок:

- Swipe: на карточке есть 2–3 причины, они не “скачут” при refresh.
- Likes/Seeking/Hot: причины согласованы по смыслу с swipe.
- Guest discover: причины тоже приходят (или fallback корректен).
- Никакие причины не раскрывают “точный адрес/точные слоты сверх того, что уже в профиле”.

---

## 7) QA acceptance checklist (для дописывания в матрицу)

Добавить в QA матрицу (как отдельный блок Task 02):

- [ ] `discoverReasons` приходит в `/users/discover` для авторизованного пользователя.
- [ ] `discoverReasons` приходит в `/users/discover/guest` для guest draft.
- [ ] На Web swipe card отображаются 2–3 причины, нет краша при пустом поле.
- [ ] На iOS swipe card отображаются 2–3 причины, нет краша при пустом поле.
- [ ] Порядок причин стабильный при повторных запросах (детерминизм).
- [ ] Причины не конфликтуют с фильтрами (если фильтр по спорту/дню — причины не противоречат).
