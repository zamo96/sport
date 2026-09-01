BEGIN;

DO $$
BEGIN
  CREATE TYPE "LocationSource" AS ENUM ('legacy', 'manual', 'geolocation');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

CREATE TABLE IF NOT EXISTS "GeoPlace" (
  "id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "providerPlaceId" TEXT NOT NULL,
  "countryCode" TEXT NOT NULL,
  "countryName" TEXT NOT NULL,
  "region" TEXT,
  "city" TEXT NOT NULL,
  "normalizedCity" TEXT NOT NULL,
  "latitude" DOUBLE PRECISION NOT NULL,
  "longitude" DOUBLE PRECISION NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "GeoPlace_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ServiceArea" (
  "id" TEXT NOT NULL,
  "locationPlaceId" TEXT NOT NULL,
  "legacyCity" TEXT,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "clubsEnabled" BOOLEAN NOT NULL DEFAULT false,
  "districtsEnabled" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ServiceArea_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "locationPlaceId" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "locationSource" "LocationSource";
ALTER TABLE "GameSearch" ADD COLUMN IF NOT EXISTS "locationPlaceId" TEXT;
ALTER TABLE "GameSearch" ADD COLUMN IF NOT EXISTS "locationCountryCode" TEXT;
ALTER TABLE "GameSearch" ADD COLUMN IF NOT EXISTS "locationCity" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "GeoPlace_provider_providerPlaceId_key" ON "GeoPlace"("provider", "providerPlaceId");
CREATE INDEX IF NOT EXISTS "GeoPlace_countryCode_normalizedCity_idx" ON "GeoPlace"("countryCode", "normalizedCity");
CREATE UNIQUE INDEX IF NOT EXISTS "ServiceArea_locationPlaceId_key" ON "ServiceArea"("locationPlaceId");
CREATE UNIQUE INDEX IF NOT EXISTS "ServiceArea_legacyCity_key" ON "ServiceArea"("legacyCity");
CREATE INDEX IF NOT EXISTS "User_locationPlaceId_accountStatus_idx" ON "User"("locationPlaceId", "accountStatus");
CREATE INDEX IF NOT EXISTS "GameSearch_locationPlaceId_isActive_searchType_status_idx" ON "GameSearch"("locationPlaceId", "isActive", "searchType", "status");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'User_locationPlaceId_fkey') THEN
    ALTER TABLE "User" ADD CONSTRAINT "User_locationPlaceId_fkey" FOREIGN KEY ("locationPlaceId") REFERENCES "GeoPlace"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'GameSearch_locationPlaceId_fkey') THEN
    ALTER TABLE "GameSearch" ADD CONSTRAINT "GameSearch_locationPlaceId_fkey" FOREIGN KEY ("locationPlaceId") REFERENCES "GeoPlace"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ServiceArea_locationPlaceId_fkey') THEN
    ALTER TABLE "ServiceArea" ADD CONSTRAINT "ServiceArea_locationPlaceId_fkey" FOREIGN KEY ("locationPlaceId") REFERENCES "GeoPlace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;

INSERT INTO "GeoPlace" ("id", "provider", "providerPlaceId", "countryCode", "countryName", "region", "city", "normalizedCity", "latitude", "longitude", "updatedAt") VALUES
  ('legacy:ru:saint-petersburg', 'legacy', 'ru:saint-petersburg', 'RU', 'Россия', 'Санкт-Петербург', 'Санкт-Петербург', 'санкт-петербург', 59.9386, 30.3141, CURRENT_TIMESTAMP),
  ('legacy:ru:moscow', 'legacy', 'ru:moscow', 'RU', 'Россия', 'Москва', 'Москва', 'москва', 55.7558, 37.6173, CURRENT_TIMESTAMP),
  ('legacy:ru:kazan', 'legacy', 'ru:kazan', 'RU', 'Россия', 'Республика Татарстан', 'Казань', 'казань', 55.7961, 49.1064, CURRENT_TIMESTAMP)
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "ServiceArea" ("id", "locationPlaceId", "legacyCity", "isActive", "clubsEnabled", "districtsEnabled", "updatedAt") VALUES
  ('service-area-saint-petersburg', 'legacy:ru:saint-petersburg', 'Санкт-Петербург', true, true, true, CURRENT_TIMESTAMP),
  ('service-area-moscow', 'legacy:ru:moscow', 'Москва', true, true, true, CURRENT_TIMESTAMP)
ON CONFLICT ("locationPlaceId") DO NOTHING;

UPDATE "User" SET
  "locationPlaceId" = CASE
    WHEN lower(trim("city")) IN ('санкт-петербург', 'санкт петербург', 'петербург', 'спб', 'saint petersburg', 'st. petersburg', 'st petersburg') THEN 'legacy:ru:saint-petersburg'
    WHEN lower(trim("city")) IN ('москва', 'moscow') THEN 'legacy:ru:moscow'
    WHEN lower(trim("city")) IN ('казань', 'kazan') THEN 'legacy:ru:kazan'
  END,
  "locationSource" = 'legacy'
WHERE "locationPlaceId" IS NULL AND "city" IS NOT NULL AND lower(trim("city")) IN (
  'санкт-петербург', 'санкт петербург', 'петербург', 'спб', 'saint petersburg', 'st. petersburg', 'st petersburg', 'москва', 'moscow', 'казань', 'kazan'
);

UPDATE "User" AS app_user SET
  "homeLat" = COALESCE((SELECT district."centerLat" FROM "District" AS district WHERE district."code" = app_user."district"), place."latitude"),
  "homeLng" = COALESCE((SELECT district."centerLng" FROM "District" AS district WHERE district."code" = app_user."district"), place."longitude")
FROM "GeoPlace" AS place
WHERE app_user."locationPlaceId" = place."id"
  AND app_user."locationPlaceId" IN ('legacy:ru:saint-petersburg', 'legacy:ru:moscow', 'legacy:ru:kazan')
  AND (app_user."homeLat" IS NULL OR app_user."homeLng" IS NULL);

UPDATE "GameSearch" AS search SET
  "locationPlaceId" = CASE
    WHEN lower(trim(court."city")) IN ('санкт-петербург', 'санкт петербург', 'петербург', 'спб', 'saint petersburg', 'st. petersburg', 'st petersburg') THEN 'legacy:ru:saint-petersburg'
    WHEN lower(trim(court."city")) IN ('москва', 'moscow') THEN 'legacy:ru:moscow'
    WHEN lower(trim(court."city")) IN ('казань', 'kazan') THEN 'legacy:ru:kazan'
  END,
  "locationCountryCode" = 'RU',
  "locationCity" = CASE
    WHEN lower(trim(court."city")) IN ('санкт-петербург', 'санкт петербург', 'петербург', 'спб', 'saint petersburg', 'st. petersburg', 'st petersburg') THEN 'Санкт-Петербург'
    WHEN lower(trim(court."city")) IN ('москва', 'moscow') THEN 'Москва'
    WHEN lower(trim(court."city")) IN ('казань', 'kazan') THEN 'Казань'
  END
FROM "Court" AS court
WHERE court."id" = COALESCE(search."preferredCourtId", search."scheduledCourtId")
  AND search."locationPlaceId" IS NULL
  AND lower(trim(court."city")) IN (
    'санкт-петербург', 'санкт петербург', 'петербург', 'спб', 'saint petersburg', 'st. petersburg', 'st petersburg', 'москва', 'moscow', 'казань', 'kazan'
  );

UPDATE "GameSearch" AS search SET
  "locationPlaceId" = owner."locationPlaceId",
  "locationCountryCode" = place."countryCode",
  "locationCity" = place."city"
FROM "User" AS owner
LEFT JOIN "GeoPlace" AS place ON place."id" = owner."locationPlaceId"
WHERE search."createdByUserId" = owner."id" AND search."locationPlaceId" IS NULL;

COMMIT;
