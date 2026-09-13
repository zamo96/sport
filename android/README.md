# SportSearch Android

Нативный Android-клиент на Kotlin + Jetpack Compose. Дизайн переносится 1:1 с
SwiftUI-приложения из [`ios/TennisSearchIOS`](../ios/TennisSearchIOS); backend
тот же самый, что у iOS и веба (`https://sportsearch.shop`).

## Что уже перенесено

**Дизайн-система** — полностью, значение в значение:

| iOS | Android |
| --- | --- |
| `enum AppTheme` | [AppTheme.kt](app/src/main/java/shop/sportsearch/app/ui/theme/AppTheme.kt) — те же RGB, тот же градиент страницы |
| `RoundedRectangle(style: .continuous)` | [ContinuousRoundedShape.kt](app/src/main/java/shop/sportsearch/app/ui/theme/ContinuousRoundedShape.kt) — сквиркл теми же кривыми Безье, что рисует Core Animation |
| `.shadow(color:radius:x:y:)` | `Modifier.appShadow` в [Modifiers.kt](app/src/main/java/shop/sportsearch/app/ui/components/Modifiers.kt) — гауссово размытие, а не Material elevation |
| `AppScreen`, `SectionCard`, `PillLabel`, `SportLevelMiniChip`, `AppInlineChip`, `EmptyStateView`, `LoadingOverlay`, `ServerRecoveryOverlay`, `FieldShell`, `Primary/SecondaryActionButtonStyle`, `AppSegmentedChoice`, `RemoteAvatarView` | [ui/components](app/src/main/java/shop/sportsearch/app/ui/components) |
| `SportIconView` | [SportIcon.kt](app/src/main/java/shop/sportsearch/app/ui/components/SportIcon.kt) — настольный теннис, падел и бадминтон нарисованы теми же путями на Canvas |
| `AppHaptics` | [Haptics.kt](app/src/main/java/shop/sportsearch/app/ui/components/Haptics.kt) |

**Слой данных** — полностью:

- [Models.kt](app/src/main/java/shop/sportsearch/app/core/Models.kt), [Enums.kt](app/src/main/java/shop/sportsearch/app/core/Enums.kt) — порт `Core/AppModels.swift`, включая `SportPlaybook`, склонения `venueTitle` и «мягкое» декодирование неизвестных значений
- [ApiClient.kt](app/src/main/java/shop/sportsearch/app/data/ApiClient.kt) — порт `Services/APIClient.swift` (OkHttp вместо URLSession), включая SSE `realtime` и санитайзинг серверных ошибок
- [LiveTennisRepository.kt](app/src/main/java/shop/sportsearch/app/data/LiveTennisRepository.kt) — все ~60 методов `protocol TennisRepository`, те же пути и тела запросов
- [AppViewModel.kt](app/src/main/java/shop/sportsearch/app/ui/AppViewModel.kt) — порт `AppModel`, включая гостевой черновик, подсказки discover и классификацию ошибок

**Экраны:**

- Онбординг и вход — интро-герой с каруселью карточек, печатающейся строкой и «жидкой» кнопкой, два шага онбординга, вход по email, OTP
- Нижний таб-бар — 1:1, включая перетаскивание пальцем по бару и compact-режим
- Главная (Discover) — тёмный экран, пилюли-табы, swipe-колода с историями, ближайшие игры, лайки, срочные поиски
- Мэтчи — список, фильтры, чат
- Мои поиски — белый экран, сводка, фильтры, карточки, FAB
- Композер срочного поиска — четыре шага (Когда / Кого / Где / Подтверждение),
  прогресс-хедер, календарь, слоты времени с округлением от текущего часа,
  выбор клуба, сводка и оверлей публикации с конфетти
- Лобби поиска — состав с подтверждёнными и ожидающими, общий чат с поллингом
  каждые 2.5 с, присутствие в лобби, предложение регулярных слотов и
  голосование за них
- Фото в чатах — системный Photo Picker (без разрешений), до 4 снимков,
  сжатие в JPEG, сетка вложений в пузыре и полноэкранный просмотр; работает
  и в личном чате, и в лобби
- Мэтчи — фильтры «Все / Новые / Нужно действие / Подтверждены / Архив» со
  счётчиками, секция входящих лайков с решением прямо в карточке, лист профиля
  игрока, лист предложения игры (спорт, дата/время, клуб, уровни, звонок в клуб
  с флоу «удалось забронировать?»), жалоба и блокировка
- Чат — карусель договорённостей, панель быстрых действий, системные события
  фотоотчёта, кнопки подтверждения/отмены игры
- Центры — поиск, фильтр по спорту, избранное, карточка клуба целиком
  (контакты, часы, цены, активные поиски, «Я хожу сюда», игроки клуба),
  профиль игрока клуба, композер личного визита
- Мои поиски — сводная полоса, фильтры и секции, карточка поиска, лист деталей
  с параметрами и ссылкой-приглашением, лист откликов с одобрением и
  отклонением, регулярные пары со слотами
- Ближайшие игры — карточки игр с обратным отсчётом, итог игры, фотоотчёты,
  личные визиты, история
- Профиль — «Редактирование / Как видят другие», карточка медиа, шкала
  заполненности, лента игр с фотоотчётами, редакторы спорта, расписания,
  локаций и уведомлений, язык, приватность, аккаунт, QR-профиль
- Уведомления — сгруппированный список с переходами по событию
- Выбор локации — страна, город, определение по геопозиции
- Карты — маршруты бега и сапборда, клубы на карте в пикере
- Обучение первого запуска — подсказка про свайпы с демо-анимацией колоды и
  зонами решения, экран «спортивный интерес отправлен» после первого лайка
- Тосты главной — `InlineToast` и `MatchSuccessToast` на всех действиях
  ближайших игр, откликов и фотоотчётов
- Ближайшие игры — лист деталей игры (участники, отклики на поиск с
  одобрением, изменить/отменить), лист клуба, лист «пригласить в игру»
- Срочные поиски на карте — переключатель «список/карта», кластеры,
  карточка выбранного поиска, лист выбора внутри кластера
- Похожие игроки на карте — схематичная раскладка по районам (тот же
  алгоритм слотов, что в iOS), карточки-аннотации, полигоны 37 районов
- Просмотренные игроки — лента возврата под колодой, автоперенос карточки в
  конец после проигрывания историй
- Виджет «Ближайшие игры» на домашнем экране — [Glance](app/src/main/java/shop/sportsearch/app/widget/UpcomingGamesWidget.kt),
  компактный и средний размер, промо-карточка и инструкция в приложении
- Онбординг целиком — сетка видов спорта 3 в ряд с плиткой «Ещё виды», лист
  выбора уровня, недельный редактор доступности с пресетами, блок «Где искать
  игроков» с двумя карточками выбора и лист «город → районы»
- Рисование маршрута бега и сапборда — тап по карте ставит точки, линия,
  спутниковый слой, отмена и очистка, превью маршрута в композере
- Клуб по адресу — подсказки адресов с сервера и «использовать введённый адрес»,
  если клуба нет в списке
- Баннер рекомендации языка при выборе страны

## Чего ещё нет

- **Пуши**: сервер отдаёт только `POST /devices/apns`, для Android нужен
  парный `devices/fcm`
- **Вход через Apple**: на Android его нет, а Google-роут на бэкенде не
  заведён, поэтому основной путь входа — email + OTP, общий у обоих клиентов
- **Live Activity**: у iOS виджета есть ActivityKit-часть с экраном блокировки
  и «динамическим островом». В Android нет аналога, ближайшее — постоянное
  уведомление, но оно ведёт себя иначе, поэтому не делалось
- **Развёрнутая карта в выборе клуба** (`SearchClubExpandedMapSheet`) и мини-
  карточка выбранного клуба под мини-картой — в пикере есть карта и список,
  но без полноэкранного режима
- **Регулярные пары**: перенесены карточка и строка занятия; лист деталей пары
  и редактор отдельного занятия (`RegularPairDetailSheet`,
  `RegularPairOccurrenceEditorSheet`) — нет
- **Обрезка видео в профиле** (`ProfileVideoTrimEditorSheet`) и лист превью
  медиа игрока

Осознанно **не** переносится:

- `SportsActivityFeedView` — в iOS она закрыта флагом
  `SportsActivityFeedPreview.isEnabled = false` и пользователям недоступна,
  так что порт сделал бы приложения разными, а не одинаковыми
- `ActiveHotSearchCalendarSheet` — в `DiscoverView.swift` объявлена, но
  `isHotSearchCalendarPresented` нигде не выставляется в `true`, то есть на
  iOS лист недостижим. Даты выбираются полосой `ActiveHotSearchDateRail`,
  которая перенесена
- `SearchComposerAdvancedSheet` — та же история в `SearchesView.swift`:
  `isAdvancedPresented` никогда не становится `true`
- **Шрифт**: iOS рисует системным SF Pro, а не брендовым шрифтом. Android-аналог
  этого выбора — системный шрифт платформы, поэтому `appFontFamily` остаётся
  `FontFamily.Default`: подстановка Inter отличалась бы и от iOS, и от веба
  (там Manrope), а не совпадала бы

## Системная кнопка «Назад»

В iOS листы закрываются свайпом вниз, в Android свайпа нет — есть системная
кнопка/жест «Назад». Поэтому каждый экран, который заменяет `.sheet`, вызывает
`DismissOnSystemBack(onDismiss)` из
[FullScreenSheet.kt](app/src/main/java/shop/sportsearch/app/ui/components/FullScreenSheet.kt).
Без этого «Назад» выходил из приложения целиком. Вложенные листы регистрируют
свои обработчики, и внутренний композится последним — поэтому «Назад» доходит
до него первым, как и на iOS.

**Добавляешь новый полноэкранный лист — добавь этот вызов первой строкой тела.**

## Карты

iOS рисует карты через MapKit, которому не нужен ключ. У Google Maps на Android
ключ обязателен, а в проекте его нет, поэтому Android использует тайлы
OpenStreetMap через [osmdroid](app/src/main/java/shop/sportsearch/app/ui/maps/AppMaps.kt):
маршруты бега и сапборда, пины клубов в пикере, срочные поиски
([ActiveHotSearchMap.kt](app/src/main/java/shop/sportsearch/app/ui/discover/ActiveHotSearchMap.kt))
и похожие игроки
([DiscoverPlayersMap.kt](app/src/main/java/shop/sportsearch/app/ui/maps/DiscoverPlayersMap.kt)).
Ключа не требуется. Если появится ключ Yandex MapKit — заменяется одним файлом.

Одно отличие от MapKit: он сам объединяет аннотации в кластеры и сам разводит
пересекающиеся карточки, у osmdroid этого нет. Кластеризация считается по
экранным координатам в самих композаблах и пересчитывается на каждый скролл и
зум, поэтому визуально ведёт себя так же.

## Как открыть

```bash
cd android && ./gradlew :app:assembleDebug
```

Собирается «из коробки»: JDK берётся из Android Studio
(`/Applications/Android Studio.app/Contents/jbr/Contents/Home` — пропиши его в
`JAVA_HOME`, если сборка идёт из терминала).

На свежем клоне из терминала нужен ещё путь к SDK — `local.properties` не в
git, он машинно-зависимый:

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
```

Android Studio создаёт `local.properties` сам при открытии проекта. Готовый APK лежит в
`app/build/outputs/apk/debug/app-debug.apk`, ~22 МБ.

Из Studio: открой папку `android` как проект и запусти конфигурацию `app`.

Тулчейн (см. [gradle/libs.versions.toml](gradle/libs.versions.toml)):
AGP 9.4.0, Gradle 9.7.1, Kotlin 2.2.20, compileSdk/targetSdk 37, minSdk 26.
Версии подобраны под установленную Android Studio AI-261 — в AGP 9 Kotlin
встроен, поэтому плагин `org.jetbrains.kotlin.android` намеренно **не**
применяется, иначе сборка падает.

## Запуск на эмуляторе

```bash
~/Library/Android/sdk/emulator/emulator -avd <avd> -dns-server 8.8.8.8
```

`-dns-server` обязателен: без него эмулятор не резолвит `sportsearch.shop` и
приложение показывает «Unable to resolve host». Проверено на AVD с образом
`system-images;android-37.0;google_apis;arm64-v8a` — онбординг, гостевой режим,
все пять вкладок и живые данные с продакшена работают.

## Локальный backend

По умолчанию оба типа сборки ходят в `https://sportsearch.shop` — так же, как
`Debug.xcconfig`/`Release.xcconfig` у iOS.

```bash
cp local.defaults.properties.example local.defaults.properties
```

Эмулятор видит хост как `10.0.2.2`; для физического устройства подставь LAN-IP
машины. Cleartext разрешён только для loopback-хостов
([network_security_config.xml](app/src/main/res/xml/network_security_config.xml)).

## Mock-режим

`USE_MOCK_DATA=YES` в `local.defaults.properties` включает
[MockRepository](app/src/main/java/shop/sportsearch/app/data/MockRepository.kt):
вход по любому email с кодом `111111`.
