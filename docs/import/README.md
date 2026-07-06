# Шаблоны импорта спортивных центров

В этой папке лежат заготовки для ручного заполнения базы спортивных центров.

## Основной файл

- [clubs.xlsx](/Users/matvey/Desktop/TennisSearch/docs/import/clubs.xlsx) — основной файл для заполнения и импорта
- [clubs.template.csv](/Users/matvey/Desktop/TennisSearch/docs/import/clubs.template.csv) — запасной CSV-шаблон с теми же колонками

## Справочники

- [sports-reference.csv](/Users/matvey/Desktop/TennisSearch/docs/import/sports-reference.csv) — допустимые коды и названия видов спорта
- [districts-reference.csv](/Users/matvey/Desktop/TennisSearch/docs/import/districts-reference.csv) — допустимые районы, которые уже поддерживает приложение
- [metros-spb.reference.csv](/Users/matvey/Desktop/TennisSearch/docs/import/metros-spb.reference.csv) — стартовый справочник станций метро Санкт-Петербурга для заполнения поля `metro`

## Формат файла клубов

Основной формат: `XLSX`.

В `clubs.xlsx` есть листы:

- `clubs` — единственный лист, который нужно заполнять и который читает импорт
- `Инструкция` — короткие правила заполнения
- `Поля` — подробное описание каждой колонки
- `Справочник спорт` — допустимые коды видов спорта
- `Справочник районы` — допустимые коды районов
- `Справочник метро` — стартовый список станций метро
- `Примеры удобств` — примеры значений для `amenities`
- `Справочник города` — подсказки для поля `city`
- `Справочник мессенджеры` — допустимые коды для `messenger_type`

Не переименовывай заголовки первой строки на листе `clubs`: импорт читает именно технические названия колонок.

В `clubs.xlsx` для справочных полей включены выпадающие списки: `city`, `sports`, `amenities`, `messenger_type`, `metro`, `district`, `district_label`. Если нужного значения нет в списке, его можно вписать вручную и добавить на соответствующий лист-справочник.

Заголовки колонок:

```csv
name,address,city,sports,phone,working_hours,yandex_maps_url,website_url,booking_url,about,amenities,messenger_type,messenger_url,photo_url,photo_file,photo_s3_key,metro,district,district_label,lat,lng
```

## Правила заполнения

- `name` — обязательно
- `address` — обязательно
- `city` — обязательно для заполнения человеком; если оставить пустым, импорт подставит город по умолчанию
- `sports` — обязательно, несколько значений через `|`
- `phone` — опционально
- `working_hours` — опционально, строкой как есть
- `yandex_maps_url` — желательно
- `website_url` — опционально, обычный сайт клуба
- `booking_url` — опционально, отдельная ссылка на онлайн-форму брони корта, поля или зала
- `about` — опционально, текст для блока «О клубе» в карточке центра
- `amenities` — опционально, список удобств через `|`, `;`, запятую или перенос строки, например `Душевые|Парковка|Кафе`
- `messenger_type` — опционально, код из листа `Справочник мессенджеры`, например `telegram` или `max`
- `messenger_url` — опционально, ссылка на мессенджер клуба, например `https://t.me/clubname`
- `telegram_url` и `max_url` тоже поддерживаются импортом как альтернативные колонки, если удобнее не заполнять `messenger_type`
- `photo_url` — опционально, готовый публичный URL фото; если заполнен, импорт использует его как есть
- `photo_file` — опционально, локальный путь до фото относительно папки с файлом `clubs.xlsx`, например `photos/tennis-prime.jpg`
- `photo_s3_key` — опционально, путь объекта в S3, например `courts/spb/tennis-prime.jpg`
- `metro` — желательно, одна или несколько ближайших станций через `|`; первая станция считается основной
- `district` — обязательно, только из `districts-reference.csv`
- `district_label` — опционально, человекочитаемое название района
- `lat` и `lng` — очень желательно для точной карты и фильтра по радиусу

## Примеры поля `sports`

```text
tennis
tennis|padel
football|volleyball|fitness
```

## Важно

- Для `sports` используй именно технические коды из `sports-reference.csv`, не русские названия.
- Для `district` используй именно технические коды из `districts-reference.csv`, не русские названия.
- Если у клуба несколько ближайших станций метро, можно указывать несколько через `|`, например `Беговая|Приморская`; первая станция станет основной в текущей модели приложения.
- Если клуб находится не в Санкт-Петербурге, обязательно заполни `city`, иначе он будет импортирован в город по умолчанию.
- Если у клуба нет сайта, телефона или фото, поле можно оставить пустым.
- Для фото заполняй либо `photo_url`, либо `photo_file`. Если указан `photo_file`, импорт загрузит файл в storage и запишет получившийся URL в `Court.photoUrl`.
- Если `photo_file` указан вместе с `photo_s3_key`, файл будет загружен в S3 именно по этому ключу. Если `photo_s3_key` не указан, ключ будет сгенерирован как `courts/import/<club-name>-<address>.<ext>`.

## S3 для фото клубов

Для загрузки фото из `photo_file` в S3 используй переменные окружения:

```bash
UPLOADS_PROVIDER=s3
S3_BUCKET=your-bucket
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_ENDPOINT=https://storage.yandexcloud.net
S3_REGION=ru-central1
S3_PUBLIC_BASE_URL=https://cdn.example.com # опционально
```

Если `UPLOADS_PROVIDER` не равен `s3`, фото сохраняются локально в `public/uploads`.

## Что дальше

Когда заполнишь CSV/XLSX, импорт можно запустить командой:

```bash
npm run clubs:import -- docs/import/clubs.xlsx
```
