# Ежедневная актуализация клубов в Яндекс Cloud

## Назначение

Агент актуализации клубов ежедневно сверяет внешние источники со справочником `Court`.

MVP работает безопасно:

- существующие клубы обновляются через стабильный `Court.id`;
- официальный сайт клуба проверяется отдельным снимком контента;
- сайт проходит analyst review: агент сравнивает факты со страницы с текущей карточкой клуба и принимает решение `apply`, `review` или `ignore`;
- опционально включается LLM analyst review: модель читает очищенный текст сайта, а при доступном браузере еще и скриншот страницы;
- новые клубы создаются в статусе `needs_review`, если явно не включен автопаблиш;
- спорные изменения названия, адреса, координат и района попадают в `CourtChangeProposal`;
- изменения телефонов, ссылок брони и сигналов закрытия с сайта попадают в `CourtChangeProposal`;
- клубы не удаляются физически, чтобы не ломать игры, регулярные пары, активности и `UserCourt`.

## Запуск

CLI:

```bash
npm run clubs:sync
```

Только обход сайтов уже известных клубов:

```bash
npm run clubs:sync -- --websites-only=1
```

Запуск с отчетом в выводе:

```bash
npm run clubs:sync -- --websites-only=1 --report=1 --report-format=markdown
```

Посмотреть последний отчет без нового запуска:

```bash
npm run clubs:report
```

Через maintenance endpoint:

```bash
curl -X POST \
  -H "Authorization: Bearer $MAINTENANCE_SECRET" \
  https://<app-host>/maintenance/clubs
```

Только сайты через endpoint:

```bash
curl -X POST \
  -H "Authorization: Bearer $MAINTENANCE_SECRET" \
  "https://<app-host>/maintenance/clubs?websitesOnly=1"
```

Запустить и сразу вернуть JSON-отчет:

```bash
curl -X POST \
  -H "Authorization: Bearer $MAINTENANCE_SECRET" \
  "https://<app-host>/maintenance/clubs?websitesOnly=1&includeReport=1"
```

Посмотреть последний JSON-отчет без запуска агента:

```bash
curl \
  -H "Authorization: Bearer $MAINTENANCE_SECRET" \
  "https://<app-host>/maintenance/clubs?reportOnly=1&sourceType=club-website"
```

Посмотреть конкретный запуск:

```bash
curl \
  -H "Authorization: Bearer $MAINTENANCE_SECRET" \
  "https://<app-host>/maintenance/clubs?reportOnly=1&runId=<run-id>"
```

Для Яндекс Cloud поставь вызов endpoint в ежедневное расписание любым текущим production-механизмом проекта: scheduled container job, serverless trigger или внешний cron, который умеет делать HTTPS-запрос с заголовком `Authorization`.

## Переменные окружения

Обязательные:

- `DATABASE_URL`
- `MAINTENANCE_SECRET` или `CRON_SECRET`
- `YANDEX_PLACES_API_KEY`

Опциональные:

- `CLUB_SYNC_PROVIDER=yandex` — источник по умолчанию.
- `CLUB_SYNC_CITY=Санкт-Петербург`
- `CLUB_SYNC_SOURCE_TYPE=yandex-places`
- `CLUB_SYNC_YANDEX_QUERIES` — список запросов через `|`, например `теннисный клуб|падел клуб|сквош клуб`.
- `CLUB_SYNC_YANDEX_RESULTS_PER_QUERY=50`
- `CLUB_SYNC_CHECK_WEBSITES=1` — после каталогов дополнительно обходить сайты клубов; включено по умолчанию для `clubs:sync`.
- `CLUB_SYNC_WEBSITES_ONLY=1` — запускать только проверку сайтов существующих клубов.
- `CLUB_SYNC_WEBSITE_LIMIT=100` — максимум сайтов за один запуск.
- `CLUB_SYNC_WEBSITE_TIMEOUT_MS=10000`
- `CLUB_SYNC_AUTO_APPLY_WEBSITE=1` — автоматически применять безопасные изменения `bookingUrl` с сайта. Телефоны и сигналы закрытия требуют ручной проверки.
- `CLUB_SYNC_PROPOSE_ANY_WEBSITE_CHANGE=1` — создавать proposal на любое изменение hash сайта, даже если не найден новый телефон/booking/closure signal.
- `CLUB_SYNC_ANALYST_MODE=hybrid` — включает LLM-аналитика поверх правил. Без этой переменной агент работает только по детерминированным правилам.
- `OPENAI_API_KEY` — нужен для `CLUB_SYNC_ANALYST_MODE=hybrid` или `llm`.
- `CLUB_SYNC_ANALYST_MODEL=gpt-4.1-mini` — модель для анализа сайта; можно переопределить.
- `CLUB_SYNC_ANALYST_TIMEOUT_MS=20000` — таймаут LLM-запроса.
- `CLUB_SYNC_ANALYST_MAX_TEXT_CHARS=16000` — сколько очищенного текста сайта отдавать модели.
- `CLUB_SYNC_ANALYST_INCLUDE_SCREENSHOT=1` — дополнительно передавать модели скриншот первого экрана сайта.
- `CLUB_SYNC_SCREENSHOT_TIMEOUT_MS=15000`
- `CLUB_SYNC_SCREENSHOT_BROWSER_PATH=/path/to/chromium` — если Chromium лежит не в стандартном пути контейнера.
- `CLUB_SYNC_AUTO_PUBLISH_NEW=1` — сразу публиковать новые клубы как `active`.
- `CLUB_SYNC_STALE_AFTER_DAYS=30` — создавать предложения на скрытие давно не найденных клубов.
- `CLUB_SYNC_AUTO_HIDE_STALE=1` — автоматически переводить давно не найденные клубы в `hidden`.

Для тестового источника вместо Yandex можно использовать JSON:

```bash
CLUB_SYNC_PROVIDER=json
CLUB_SYNC_JSON_FILE=/path/to/clubs.json
```

Формат JSON: массив объектов или объект `{ "clubs": [...] }` с полями `name`, `address`, `sports`, `locationLat`, `locationLng` и опциональными контактами.

## Проверка результата

После запуска смотри отчет:

- `npm run clubs:report` локально или на сервере;
- `/maintenance/clubs?reportOnly=1&sourceType=club-website` через production endpoint;
- `/maintenance/clubs?reportOnly=1&runId=<run-id>` для конкретного запуска.

В секциях `Applied Changes` и `Pending Review` отчет показывает старое и новое значение в формате `field: old -> new`, режим `auto`/`review`, confidence, reason и evidence-фрагмент страницы, по которому агент принял решение.

Секция `Analyst Errors` показывает случаи, когда сайт скачался, но LLM-аналитик или screenshot-этап не сработал. Это не считается падением проверки сайта: правила все равно могут создать proposal, а причину сбоя можно отдельно починить в окружении.

LLM-аналитик не применяет изменения автоматически. Его предложения по телефону, адресу, часам, видам спорта, описанию и признакам закрытия попадают в `Pending Review`. Автоприменение остается только для безопасной `bookingUrl`, найденной правилами на том же домене.

В БД отчет строится из таблиц:

- `CourtSyncRun` — статус и счетчики запуска;
- `CourtChangeProposal` — новые, спорные или stale-изменения;
- `CourtWebsiteCheck` — результат каждой проверки сайта, hash контента, найденные телефоны и booking-ссылки;
- `Court.status` — `active`, `needs_review`, `hidden`, `archived`;
- `/play/courts` — публичный список показывает только `active`.

## Риски

- Yandex Places API возвращает релевантную выдачу, но не гарантирует полный список всех клубов города.
- Сайты клубов могут содержать динамические блоки, поэтому по умолчанию proposal создается только при найденных изменениях телефонов, booking-ссылок или сигналов закрытия/переезда.
- LLM-аналитик повышает качество разбора сложных сайтов, но может ошибаться; поэтому его изменения не автоприменяются.
- Vision-режим требует доступного Chromium/Playwright в production-контейнере. Если браузера нет, отчет покажет screenshot error, а текстовый анализ и правила продолжат работать.
- Категории источника могут быть шире нашей спортивной модели, поэтому новые клубы безопаснее ревьюить перед публикацией.
- Автоскрытие старых клубов лучше включать только после нескольких стабильных запусков и ручной проверки покрытия источника.
