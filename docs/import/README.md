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
name,address,sports,phone,working_hours,yandex_maps_url,website_url,photo_url,metro,district,lat,lng
```

## Правила заполнения

- `name` — обязательно
- `address` — обязательно
- `sports` — обязательно, несколько значений через `|`
- `phone` — опционально
- `working_hours` — опционально, строкой как есть
- `yandex_maps_url` — желательно
- `website_url` — опционально
- `photo_url` — опционально, пока один URL на карточку
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

## Что дальше

Когда заполнишь CSV, следующим шагом можно будет:

1. добавить импорт-скрипт под Prisma
2. проверить строки на валидность
3. залить данные в базу одной командой
