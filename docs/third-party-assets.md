# Third-party assets and data

## iOS onboarding city thumbnails

- `OnboardingCitySaintPetersburg`: “Saint Petersburg Palace Bridge, St. Petersburg (37931957696)” by Michael Kuhn (`kuhnmi`), cropped and resized, licensed under [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/). Source: [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Saint_Petersburg_Palace_Bridge,_St._Petersburg_(37931957696).jpg).
- `OnboardingCityMoscow`: “Moscow-Kremlin” by Роман396, cropped and resized, released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Source: [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Moscow-Kremlin.jpg).

## SimpleMaps World Cities Database

The global location picker uses the Basic World Cities Database distributed through `world-cities-json@1.0.1`.

- Source: https://simplemaps.com/data/world-cities
- Package: https://www.npmjs.com/package/world-cities-json
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
- Attribution: © SimpleMaps.com

The application uses city names, administrative regions, country codes, coordinates, population estimates, and stable dataset identifiers. API responses expose attribution metadata so user-facing clients can retain the required credit.

## GeoNames Russian names

Russian display names for SimpleMaps catalog rows are matched to the GeoNames RU country dump and Russian-language alternate names by coordinates and aliases. Only the compact SimpleMaps-ID-to-name result is included in the application; raw GeoNames dumps are not distributed.

- Source: https://download.geonames.org/export/dump/
- Project: https://www.geonames.org/
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
- Attribution: GeoNames
