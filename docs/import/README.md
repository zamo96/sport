# Шаблоны импорта спортивных центров

В этой папке лежат заготовки для ручного заполнения базы спортивных центров.

## Основной файл

- [clubs.template.csv](/Users/matvey/Desktop/TennisSearch/docs/import/clubs.template.csv) — основной шаблон клубов

## Справочники

- [sports-reference.csv](/Users/matvey/Desktop/TennisSearch/docs/import/sports-reference.csv) — допустимые коды и названия видов спорта
- [districts-reference.csv](/Users/matvey/Desktop/TennisSearch/docs/import/districts-reference.csv) — допустимые районы, которые уже поддерживает приложение
- [metros-spb.reference.csv](/Users/matvey/Desktop/TennisSearch/docs/import/metros-spb.reference.csv) — стартовый справочник станций метро Санкт-Петербурга для заполнения поля `metro`

## Формат файла клубов

Формат: `CSV UTF-8`

Заголовки колонок:

```csv
name,address,sports,phone,working_hours,yandex_maps_url,website_url,photo_url,photo_file,photo_s3_key,metro,district,lat,lng
```

## Правила заполнения

- `name` — обязательно
- `address` — обязательно
- `sports` — обязательно, несколько значений через `|`
- `phone` — опционально
- `working_hours` — опционально, строкой как есть
- `yandex_maps_url` — желательно
- `website_url` — опционально
- `photo_url` — опционально, готовый публичный URL фото; если заполнен, импорт использует его как есть
- `photo_file` — опционально, локальный путь до фото относительно папки с файлом `clubs.xlsx`, например `photos/tennis-prime.jpg`
- `photo_s3_key` — опционально, путь объекта в S3, например `courts/spb/tennis-prime.jpg`
- `metro` — желательно, одна ближайшая станция
- `district` — обязательно, только из `districts-reference.csv`
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
- Если у клуба несколько ближайших станций метро, для MVP указывай одну главную.
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
