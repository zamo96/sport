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

- `Debug` запускается с `USE_MOCK_DATA = YES`
- `Release` ожидает живой backend

## Как включить live backend

1. Подними текущий web/backend проект.
2. В [Debug.xcconfig](/Users/matvey/Desktop/TennisSearch/ios/TennisSearchIOS/Configs/Debug.xcconfig) установи:

```xcconfig
API_BASE_URL = http://localhost:3002
USE_MOCK_DATA = NO
```

3. Если работаешь на iOS Simulator, `localhost` будет указывать на Mac-хост, этого достаточно.
4. Для физического устройства укажи IP машины в сети вместо `localhost`.

## Mock вход

- email: любой
- код: `111111`

## Ограничения текущей первой iOS-сборки

- не перенесены web-specific карты Яндекса, вместо них используется `MapKit`
- не добавлены пуши, загрузка аватара и deep linking
- не вынесены все server-side aggregated представления `discover/hot/likes`, iOS пока работает с базовыми REST-маршрутами
