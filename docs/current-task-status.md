# Текущий Статус Задачи

## Активная Верхнеуровневая Задача

`Task 02 / Design Alignment For Onboarding, Player Cards, Modals And Sport-Specific Game Flow`

## Общий Статус

`в_работе`

## Последнее Обновление

`2026-04-20 19:31:56 MSK`

## Что Уже Сделано

- `Task 01` доведен до статуса `готово_к_приемке`; его итог не потерян и остается доступным для Product Owner review
- собран новый product audit по `onboarding`, `player card`, `modal / sheet`, sport-specific game parameters и status model
- зафиксирован продуктовый контракт по `onboarding / player card / modal vs inline`:
  - `/Users/matvey/Desktop/TennisSearch/docs/task-02-product-brief.md`
- зафиксирован технический контракт explainability для discover/player card:
  - `/Users/matvey/Desktop/TennisSearch/docs/task-02-technical-design.md`
- зафиксирован новый task packet:
  - `/Users/matvey/Desktop/TennisSearch/docs/task-packet-iteration-01-task-02.md`
- зафиксирован внутренний ночной execution plan:
  - `/Users/matvey/Desktop/TennisSearch/docs/iteration-01-night-execution-plan-task-02.md`
- зафиксирован обязательный сценарный visual review:
  - `/Users/matvey/Desktop/TennisSearch/docs/design-review-scenarios.md`
- screenshots по шагам сценариев теперь являются обязательной частью утреннего отчета
- зафиксировано operational rule для Web review:
  - если после серверных изменений локальный runtime падает, команда должна заново поднимать его через `npm run dev`
- обновлена QA verification matrix под Task 02:
  - `/Users/matvey/Desktop/TennisSearch/docs/qa-matrix-iteration-01-task-02.md`
- зафиксирован и внедрён первый вариант `sport playbook` как source of truth:
  - Web + backend shared: `/Users/matvey/Desktop/TennisSearch/src/lib/sport-playbook.ts`
  - iOS shared: `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Core/AppModels.swift`
- подтверждено ограничение среды для iOS visual review:
  - полный Xcode доступен через `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  - `xcodebuild` в таком режиме работает
  - `simctl` / iOS Simulator доступны; базовые screenshots сняты (глубокие шаги сценариев требуют ручной навигации)
- зафиксирован первый вариант `canonical status map` для UI-лейблов:
  - `/Users/matvey/Desktop/TennisSearch/src/lib/status-map.ts`
- добавлены unit-тесты для `status map` (защита от регресса copy/маппинга):
  - `/Users/matvey/Desktop/TennisSearch/tests/status-map.test.ts`
- Web формы создания поиска/игры стали sport-aware (format + playersNeeded + duration defaults):
  - `/Users/matvey/Desktop/TennisSearch/src/components/forms/game-search-form.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/components/forms/game-request-form.tsx`
- Discover выдача теперь содержит explainability reasons (2–4 причины “почему этот игрок в подборе”) без изменения ранжирования:
  - `/Users/matvey/Desktop/TennisSearch/src/lib/scoring.ts`
  - `/Users/matvey/Desktop/TennisSearch/src/server/discover.ts`
  - `/Users/matvey/Desktop/TennisSearch/src/server/serializers.ts`
  - `/Users/matvey/Desktop/TennisSearch/tests/explainability.test.ts`
- Explainability reasons теперь действительно прокинуты end-to-end в Web UI (swipe/likes/seeking/hot) и используются как primary источник (fallback остаётся только при пустом поле):
  - `/Users/matvey/Desktop/TennisSearch/src/app/discover/page.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/components/discover/incoming-likes-list.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/components/discover/seeking-players-list.tsx`
- Web onboarding и player card усилены под новый контракт (включая секцию “Почему в подборе”):
  - `/Users/matvey/Desktop/TennisSearch/src/app/onboarding/page.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/components/discover/swipe-deck.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/components/discover/discover-intro-sheet.tsx`
- Discover intro (“Как устроен поиск”) теперь реально показывается как sheet на `/discover` (и в guest discover) и не конкурирует с другими оверлеями в первом заходе:
  - `/Users/matvey/Desktop/TennisSearch/src/app/discover/page.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/components/discover/guest-discover-screen.tsx`
- iOS редактор поиска теперь ограничивает формат по виду спорта и держит дефолты синхронно с playbook:
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/SearchesView.swift`
- Web sheets (Discover intro + AuthRequired) больше не допускают фонового скролла и лучше контролируют клавиатуру (Escape / фокус):
  - `/Users/matvey/Desktop/TennisSearch/src/components/ui/use-lock-body-scroll.ts`
  - `/Users/matvey/Desktop/TennisSearch/src/components/discover/discover-intro-sheet.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/components/auth/auth-required-sheet.tsx`
- Backend PATCH для смены статусов стал идемпотентным (важно для ретраев и предотвращения дублей системных сообщений):
  - `/Users/matvey/Desktop/TennisSearch/src/app/game-search-responses/[id]/route.ts`
  - `/Users/matvey/Desktop/TennisSearch/src/app/game-requests/[id]/route.ts`
- Canonical status map стал более единым: убраны локальные маппинги статуса отклика и дублирующая функция перевода статуса game request:
  - `/Users/matvey/Desktop/TennisSearch/src/app/play/searches/page.tsx`
  - `/Users/matvey/Desktop/TennisSearch/src/lib/game-requests.ts`
  - `/Users/matvey/Desktop/TennisSearch/src/lib/status-map.ts`
  - `/Users/matvey/Desktop/TennisSearch/tests/status-map.test.ts`
- Explainability reasons: улучшена стабильность и покрытие edge cases (district fallback без утечек):
  - `/Users/matvey/Desktop/TennisSearch/src/lib/scoring.ts`
  - `/Users/matvey/Desktop/TennisSearch/tests/explainability.test.ts`
- iOS: убран nested sheet в `SearchesView` (исправление правила “без sheet поверх sheet”):
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/SearchesView.swift`
- iOS теперь принимает `explainabilityReasons` из API и показывает их на swipe card и в participant sheet:
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Core/AppModels.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/DiscoverView.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Services/MockRepository.swift`
- iOS onboarding и player sheets выровнены по смыслу с Web (обязательное/можно позже + next step + “Почему…”):
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/AuthView.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/DiscoverView.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/MatchesView.swift`
- shared validation теперь запрещает несовместимые `sport + format` (важно для Web/iOS/backdoor API):
  - `/Users/matvey/Desktop/TennisSearch/src/lib/validators.ts`
- добавлены unit-тесты для `sport playbook` (защита от регресса defaults/ограничений):
  - `/Users/matvey/Desktop/TennisSearch/tests/sport-playbook.test.ts`
- добавлен канонический helper для sport-aware семантики `формат`/`место` и интегрирован в Web/iOS:
  - Web/shared helper: `/Users/matvey/Desktop/TennisSearch/src/lib/sport-semantics.ts`
  - Web UI re-export: `/Users/matvey/Desktop/TennisSearch/src/components/sport-semantics.ts`
  - unit-тесты: `/Users/matvey/Desktop/TennisSearch/tests/sport-semantics.test.ts`
- iOS: sport-aware `место`/`формат` выровнены с playbook (boxing/fitness/yoga не выглядят как “корт”; football/volleyball не “парный”):
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Core/AppModels.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/SearchesView.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/DiscoverView.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/MatchesView.swift`
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Views/UIComponents.swift`
- iOS: Debug окружение выровнено под локальный запуск (чтобы можно было “зайти” без внешнего бэкенда):
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Configs/Debug.xcconfig` (`USE_MOCK_DATA=YES`, `API_BASE_URL=127.0.0.1:3002`)
  - `/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Info.plist` (ATS exception domains для `127.0.0.1` и `localhost`)
- зафиксированы артефакты visual review (screenshots):
  - iOS: `/Users/matvey/Desktop/TennisSearch/.artifacts/design-review/ios/01-onboarding/step-01-launch.png`
  - iOS: `/Users/matvey/Desktop/TennisSearch/.artifacts/design-review/ios/02-discover-card/step-01-discover.png`
  - Web: `/Users/matvey/Desktop/TennisSearch/.artifacts/design-review/web/01-onboarding/step-01-auth-email.png`
  - Web: `/Users/matvey/Desktop/TennisSearch/.artifacts/design-review/web/02-discover-card/step-01-discover.png`
  - Web: `/Users/matvey/Desktop/TennisSearch/.artifacts/design-review/web/03-create-search/step-01-open-regular.png`
  - Web: `/Users/matvey/Desktop/TennisSearch/.artifacts/design-review/web/03-create-search/step-02-open-hot.png`
  - Web: `/Users/matvey/Desktop/TennisSearch/.artifacts/design-review/web/04-proposal/step-01-open-proposal.png`
- проверки:
  - `npm run test` ✅
  - `npm run lint` ✅
  - `npm run build` ✅ (включая `prisma generate`)
  - `xcodebuild` ✅ (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, `-sdk iphonesimulator`)
  - `simctl` / iOS Simulator ✅
  - Web runtime: ✅ отвечает на `http://127.0.0.1:3002`

## Что Команда Делает Сейчас

- запускает ночной hourly-прогон по `Task 02`
- держит `sport playbook` и `status map` как frozen sources of truth
- встраивает explainability reasons в player card на Web/iOS без изменения ranking/eligibility
- готовит следующий шаг: выровнять modal/sheet surfaces под правила из product brief (без тяжёлого redesign discover)
- отдельно добавляет в контракт два фокуса:
- отдельно добавляет в контракт три фокуса:
  - убрать iOS contrast/readability failures
  - сделать `court / format` semantics sport-aware
  - проходить основные product scenarios пошагово и фиксировать дизайн каждого шага

## Что Должно Произойти Дальше

- shared contract по статусам и sport defaults должен быть заморожен до активных UI-изменений
- Web и iOS должны получить согласованный смысл `onboarding` и `player card`
- формы создания игры должны стать чувствительными к выбранному виду спорта
- labels для `места` и `формата` должны перестать быть универсальными и начать зависеть от спорта и числа участников
- к утру команда должна собрать отчет по прогрессу, проверкам и рискам

## Контекст По Предыдущей Задаче

- `Task 01` остается в статусе `готово_к_приемке`
- его результат не блокирует запуск `Task 02`
- если потребуется финальная приемка по `Task 01`, команда вернет короткий acceptance summary отдельно

## Правило Видимости Для Product Owner

Этот файл остается тихим индикатором прогресса по текущей верхнеуровневой задаче.

Он обновляется только при существенном сдвиге по задаче целиком, а не по каждой внутренней фазе или мелкому техническому шагу.

## Действие Со Стороны Product Owner

`действие не требуется; команда ушла в ночной прогон`
