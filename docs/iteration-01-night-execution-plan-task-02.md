# Ночной План Команды

## Задача

`Iteration 01 / Task 02 / Design Alignment For Onboarding, Player Cards, Modals And Sport-Specific Game Flow`

## Цель Ночного Прогона

До утра продвинуть продукт в четырех связанных направлениях:

- ясный onboarding
- сильная player card
- sport-specific game creation
- единая статусная модель игры
- readable iOS design без contrast failures

## Внутренний Ритм Команды

Команда работает hourly-циклом.

На каждом цикле:

1. Orchestrator проверяет текущее состояние task packet и status file.
2. Product Analyst и Solution Architect при необходимости уточняют contract freeze.
3. Backend, Frontend, Mobile и Matching берут независимые куски работы.
4. QA обновляет verification matrix и проверяет новые риски.
5. Orchestrator обновляет status file только при существенном сдвиге по задаче целиком.

Отдельное правило:

- visual review идет по сценариям из `/Users/matvey/Desktop/TennisSearch/docs/design-review-scenarios.md`, а не по случайным отдельным экранам
- screenshots по шагам должны быть пригодны для прямого включения в утренний отчет
- перед прохождением Web-сценариев команда должна проверять локальный runtime; если сервер не отвечает после изменений, команда обязана поднять его через `npm run dev`

## Ownership По Ночным Потокам

### Поток 1. Product Contract

Owner:

- Product Analyst
- Solution Architect

Результат:

- единый `canonical status map`
- единый `sport playbook`
- единый список обязательных блоков `player card`
- правила использования `modal / sheet`

### Поток 2. Web Design And UX

Owner:

- Frontend Agent

Результат:

- более ясный `onboarding`
- более сильная `player card`
- переработанные Web modal surfaces
- sport-aware формы создания игры
- sport-aware labels для `формат` и `место`

### Поток 3. iOS Design And UX

Owner:

- Mobile Agent

Результат:

- iOS onboarding ближе по смыслу к Web
- iOS detail/sheet flow менее фрагментирован
- iOS статусные тексты и next steps согласованы с Web
- локализованы и исправлены очевидные contrast problems
- при доступном полном Xcode выполнен simulator-based visual pass
- screenshots из Simulator сохранены как визуальная база для дизайн-решений команды

### Поток 4. Shared Domain Logic

Owner:

- Backend Agent
- Matching Agent

Результат:

- status helpers не дублируются
- sport defaults находятся в shared source of truth
- player card может показывать понятные explainability reasons
- presentation helpers умеют различать `корт` и другой тип локации по виду спорта
- presentation helpers умеют выдавать human-readable label для группового и командного формата

### Поток 5. Verification

Owner:

- QA Agent

Результат:

- regression matrix по core flow
- проверка status consistency
- проверка sport-specific field behavior

## Жесткие Правила Ночного Прогона

- не запускать два агента на один и тот же shared helper, route или schema-файл
- не менять статусную семантику одновременно в backend и UI без contract freeze
- не уводить задачу в полный redesign discover
- не добавлять premium scope
- не ломать `Task 01` semantics вокруг `confirmed game`
- не оставлять на iOS экраны с темным текстом на темном фоне
- не использовать `корт` как универсальный label для спорта, где уместнее `зал`, `клуб`, `студия` или `площадка`
- не показывать `Парная`, если по сути это групповой или командный сценарий с количеством участников больше 2

## Что Считать Успехом К Утру

- есть ощутимый прогресс в коде, а не только в документах
- статусная карта стала понятнее и ближе к единому словарю
- onboarding и player card стали ближе к product-ready виду
- формы создания игры лучше учитывают выбранный спорт
- iOS readability issues локализованы и закрыты или явно перечислены как риск среды
- команда оставила утренний отчет с проверками, рисками и следующим рекомендованным шагом
- команда смогла пройти основные пользовательские сценарии и зафиксировать дизайн каждого ключевого шага
- в утреннем отчете есть screenshots по сценариям и шагам, а не только текстовый summary
