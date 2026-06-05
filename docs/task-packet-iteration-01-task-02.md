# Task Packet

## Название

`Iteration 01 / Task 02 / Design Alignment For Onboarding, Player Cards, Modals And Sport-Specific Game Flow`

## Запрос

Подготовить и запустить ночную работу команды по следующему верхнеуровневому направлению:

- улучшить дизайн и информационную архитектуру `onboarding`
- пересобрать состав и иерархию `player card`
- привести `modal / sheet`-паттерны к осмысленному использованию
- сделать параметры создания игры зависящими от выбранного вида спорта
- зафиксировать единую статусную карту создаваемых и принимаемых игр

## Почему Эта Задача Следующая

`Task 01` уже довел core flow до более понятного `confirmed game`, но теперь продукт упирается в следующий слой качества:

- пользователь не всегда быстро понимает, что обязательно на входе в продукт
- карточка игрока содержит данные, но не всегда объясняет, почему этот игрок релевантен и что делать дальше
- модальные сценарии иногда прерывают поток вместо того, чтобы снижать неопределенность
- форма создания игры недостаточно учитывает различия между видами спорта
- статусная модель домена остается технически рабочей, но продуктово разрозненной

## Продуктовая Цель

Сделать путь от первого входа в продукт до осмысленного создания или принятия игры заметно понятнее на Web и iOS за счет:

1. более ясного `onboarding`
2. более сильной `player card`
3. более аккуратной `modal / sheet` логики
4. sport-specific параметров игры
5. единого статусного словаря игровых сущностей

## Scope

### In Scope

- redesign информационной и смысловой структуры `onboarding`
- redesign состава `player card` и порядка информации на ней
- rules для `modal / sheet / detail` presentation
- canonical `sport playbook` для параметров создания игры
- canonical `status map` для search / response / game request / regular pair / regular occurrence
- iOS readability audit для темных экранов и темных контейнеров
- sport-aware labels для `court / venue / location`
- format display layer, которая не называет групповые и командные сценарии `парными`
- выравнивание Web и iOS вокруг одного словаря статусов и `next step`
- backend/helper changes, если они нужны для product-contract alignment

### Out Of Scope

- premium redesign
- полноформатный redesign всего discover
- новая recommendation model
- no-show policy redesign
- release automation
- крупная schema migration, если задачу можно решить через shared config и helper alignment

## Затрагиваемые Домены

- профиль пользователя
- вид спорта и уровень игрока
- геолокация и район
- доступность и тайм-слоты
- game request / proposal lifecycle
- game search / lobby lifecycle
- discover card composition
- модальные и sheet-представления
- статусная карта игры

## Что Должно Получиться К Утру

- зафиксирован и внедрен единый продуктовый словарь статусов
- Web и iOS показывают более согласованный смысл `onboarding` и `player card`
- формы создания игры лучше подстраиваются под выбранный вид спорта
- модальные паттерны используются осознаннее и меньше ломают основной поток
- есть утренний отчет команды с итогом по сделанному, проверкам и рискам
- команда прошла основные product scenarios и зафиксировала визуальный материал по шагам
- утренний отчет содержит screenshots интерфейса по сценариям для каждого шага, где это технически возможно

## Contract Freeze Перед Реализацией

Перед активной параллельной реализацией команда должна зафиксировать два источника правды:

1. `canonical status map`
2. `sport playbook`

### Canonical Status Map

Доменный уровень:

- `GameSearch`: `active / in_review / matched / closed`
- `GameSearchResponse`: `pending / approved / rejected / withdrawn`
- `GameRequest`: `pending / accepted / declined / canceled`
- `RegularPair`: `active / paused / closed`
- `RegularPairOccurrence`: `pending / confirmed / declined / canceled / expired`

Пользовательский смысловой уровень:

- `идет набор`
- `ожидает решения`
- `игра подтверждена`
- `неактивно`
- `завершено`

Правило:

- `GameSearch` описывает только поиск и набор
- `GameRequest` или `RegularPairOccurrence.confirmed` описывают конкретную запланированную игру
- UI не изобретает собственные статусы, а только отображает канонический словарь

### Sport Playbook

Для каждого вида спорта команда должна зафиксировать:

- допустимые `format`
- рекомендуемый `playersNeeded`
- ожидания по `duration`
- нужна ли выраженная привязка к корту или нужен другой тип локации
- какие поля обязательны в `hot` и `regular` сценарии
- как подавать `level range`
- какой copy и какие hints использовать в формах
- какой user-facing label использовать для места: `корт`, `зал`, `клуб`, `студия`, `площадка`

Дополнительные правила:

- `boxing`, `fitness`, `yoga` и другие не-court-first сценарии не должны в UI подаваться как игра на корте
- `court` должен быть только частным случаем location semantics, а не универсальным словом во всех карточках и формах

Минимально покрыть:

- `tennis`
- `padel`
- `badminton`
- `table_tennis`
- `squash`
- `football`
- `volleyball`

### Format Display Semantics

Команда должна прекратить выводить сырой enum-label, если он ломает продуктовый смысл.

Нужен sport-aware display layer:

- `singles` -> `Одиночная` или `Индивидуально`, в зависимости от спорта
- `doubles` -> `Парная`, только если это действительно сценарий 2x2
- сценарии с `playersNeeded > 2` в футболе, волейболе и других групповых видах спорта не должны показываться как `Парная`
- для таких сценариев UI должен уметь показывать смысловой label уровня `Групповая` или `Командная`

## Роли Агентов И Параллельные Контуры

### Orchestrator / Tech Lead Agent

- фиксирует `contract freeze`
- раздает ownership без конфликтов
- следит, чтобы Web, iOS и backend не разошлись по смыслу
- собирает утренний итог

### Product Analyst Agent

- формулирует новый смысл `onboarding`
- определяет обязательный состав `player card`
- задает правила, когда использовать `modal / sheet`, а когда inline detail
- формирует acceptance criteria для `sport playbook`

### Solution Architect Agent

- фиксирует `canonical status map`
- определяет единый модуль-источник правды для sport-specific defaults
- решает, какие изменения остаются на уровне helper/config, а какие требуют backend mutation changes

### Backend Agent

- выносит sport-specific defaults и status interpretations в shared helpers/config
- убирает дублирование статусов и copy на уровне route serialization, если это мешает alignment
- сохраняет API-consistency для Web и iOS

### Frontend Agent

- пересобирает Web `onboarding`
- пересобирает Web `player card`
- приводит Web modal/sheet presentation к новой модели
- обновляет формы создания игры под `sport playbook`

### Mobile Agent

- выравнивает iOS `onboarding` по смыслу с Web
- пересобирает iOS player detail / sheet hierarchy
- обновляет iOS поиск/создание игры и статусные тексты под общий contract
- проводит contrast-аудит ключевых экранов на iOS
- если в окружении доступен полный Xcode, обязан использовать iOS Simulator для визуальной проверки ключевых экранов

### Matching / Recommendation Agent

- определяет 2-4 explainability reasons для `player card`, основанных на спорте, уровне, расстоянии и доступности
- следит, чтобы sport-specific presentation не ломала ranking eligibility
- не меняет lifecycle игры, только explainability и совместимость

### QA Agent

- строит regression matrix для `onboarding -> discover -> create/search/respond -> confirmed game`
- отдельно валидирует status map и consistency между Web и iOS
- отдельно валидирует sport-specific defaults на формах

## Safe Parallelization Plan

Сначала:

1. Product Analyst + Solution Architect фиксируют `contract freeze`
2. QA строит verification matrix

После freeze можно параллельно:

- Backend Agent: shared helpers, status map, sport playbook config
- Frontend Agent: Web onboarding, cards, forms, modal structure
- Mobile Agent: iOS onboarding, cards, sheets, status wording
- Matching Agent: explainability reasons и совместимость с ranking logic

Финально:

- QA Agent проводит проверку
- Orchestrator собирает единый итог

## Обязательные Дизайн-Правила Для Этого Прогона

- на iOS не допускаются темные тексты на темных поверхностях и другие очевидные contrast failures
- при наличии полного Xcode visual pass через Simulator обязателен минимум для `onboarding`, `discover`, `player card`, `search/create game`, `sheet/modal`
- visual pass должен опираться не только на код, но и на реальные screenshots из Simulator
- visual review должен быть сценарным и идти по `/Users/matvey/Desktop/TennisSearch/docs/design-review-scenarios.md`
- screenshots должны попадать в итоговый отчет, а не оставаться только внутренним артефактом команды
- перед Web visual review команда обязана проверить, что локальный dev-сервер реально работает; если сервер упал после изменений, нужно заново поднять его через `npm run dev`
- если полного Xcode нет, это должно быть явно отражено в рисках как ограничение среды
- слово `корт` не должно использоваться как универсальный label для всех видов спорта
- display label формата должен зависеть не только от enum `PlayFormat`, но и от спорта и фактического количества участников

## Предполагаемые Модули

### Web

- `/Users/matvey/Desktop/TennisSearch/src/app/onboarding/page.tsx`
- `/Users/matvey/Desktop/TennisSearch/src/components/forms/profile-form.tsx`
- `/Users/matvey/Desktop/TennisSearch/src/components/discover/swipe-deck.tsx`
- `/Users/matvey/Desktop/TennisSearch/src/components/discover/discover-intro-sheet.tsx`
- `/Users/matvey/Desktop/TennisSearch/src/components/forms/game-search-form.tsx`
- `/Users/matvey/Desktop/TennisSearch/src/components/forms/game-request-form.tsx`

### Backend / Shared

- `/Users/matvey/Desktop/TennisSearch/src/lib/game-search.ts`
- `/Users/matvey/Desktop/TennisSearch/src/lib/game-requests.ts`
- `/Users/matvey/Desktop/TennisSearch/src/lib/sport-levels.ts`
- `/Users/matvey/Desktop/TennisSearch/src/server/matching.ts`
- `/Users/matvey/Desktop/TennisSearch/src/server/discover.ts`
- `/Users/matvey/Desktop/TennisSearch/src/app/game-search-responses/[id]/route.ts`

### iOS

- `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/AuthView.swift`
- `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/DiscoverView.swift`
- `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/SearchesView.swift`
- `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/MatchesView.swift`
- `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Core/AppModels.swift`

### QA / Tests

- `/Users/matvey/Desktop/TennisSearch/tests/game-search.test.ts`
- `/Users/matvey/Desktop/TennisSearch/tests/game-request.test.ts`
- `/Users/matvey/Desktop/TennisSearch/tests/matching.test.ts`

## Definition Of Done Для Этой Ночной Задачи

- зафиксирован и применен `canonical status map`
- зафиксирован и применен `sport playbook`
- Web и iOS показывают более согласованный `onboarding`
- `player card` стала информативнее и яснее по следующему действию
- modal/sheet usage стал осознаннее
- iOS readability issues локализованы и исправлены или явно перечислены как остаточный риск
- location semantics и format semantics приведены к sport-aware виду
- пройдены `npm run test`, `npm run lint`, `npm run build`
- если затронут iOS и есть окружение, прогнан `xcodebuild`
- есть утренний отчет с рисками и открытыми follow-up
