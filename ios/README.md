# TennisSearch iOS

Нативный SwiftUI-клиент для текущего backend из этого репозитория.

## Что уже перенесено

- вход по email + OTP
- табы `Поиск / Мэтчи / Поиски / Центры / Профиль`
- быстрый swipe-flow для подбора игроков
- список мэтчей и чат
- список своих поисков и создание нового поиска
- список спортивных центров с `MapKit`
- редактирование профиля и notification-настроек
- `mock`-режим для локального просмотра без backend
- `live`-режим через REST API текущего Next.js приложения

## Как открыть в Xcode

1. Открой [TennisSearchIOS.xcodeproj](/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS.xcodeproj).
2. Выбери target `TennisSearchIOS`.
3. В `Signing & Capabilities` укажи свой `Team`.
4. Запусти на симуляторе iPhone.

## Режимы запуска

Настройки лежат в:

- [Debug.xcconfig](/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Configs/Debug.xcconfig)
- [Release.xcconfig](/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Configs/Release.xcconfig)

По умолчанию:

- `Debug` и `Release` используют публичный live backend `https://sportsearch.shop`
- `USE_MOCK_DATA = NO`
- Debug-сборка не зависит от разрешения на поиск устройств в локальной сети

## Как подключить локальный backend

1. Подними текущий web/backend проект.
2. Скопируй пример локальной конфигурации:

```sh
cp ios/TennisSearchIOS/Configs/Local.xcconfig.example \
  ios/TennisSearchIOS/Configs/Local.xcconfig
```

`Local.xcconfig` подключается в конце `Debug.xcconfig`, переопределяет его значения и не попадает в Git.

3. Для iOS Simulator можно использовать:

```xcconfig
API_SCHEME = http
API_BASE_URL = 192.168.0.102:3000
USE_MOCK_DATA = NO
ALLOW_DEBUG_SERVER_TRUST = YES
```

4. Для физического устройства замени `localhost` на LAN IP машины, например `192.168.1.100:3000`. Устройство и Mac должны находиться в одной сети, а приложению нужно разрешить поиск устройств в локальной сети. Если отказать в этом разрешении, локальный backend с физического устройства будет недоступен; публичный backend продолжит работать.

## Как включить mock-режим

Добавь в `Local.xcconfig`:

```xcconfig
USE_MOCK_DATA = YES
```

Удаление `Local.xcconfig` возвращает Debug-сборку к публичному live backend.

## Mock вход

- email: любой
- код: `111111`

## Ограничения текущей первой iOS-сборки

- не перенесены web-specific карты Яндекса, вместо них используется `MapKit`
- не добавлены пуши, загрузка аватара и deep linking
- не вынесены все server-side aggregated представления `discover/hot/likes`, iOS пока работает с базовыми REST-маршрутами
