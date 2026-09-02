BEGIN;

-- Дайджест «Срочно» переехал на движок кампаний: идемпотентность теперь даёт
-- NotificationDelivery.dedupeKey, поэтому переносим историю доставок и убираем
-- отдельную таблицу. Без переноса игроки получили бы дубль за текущий слот.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = current_schema() AND table_name = 'HotSearchDigestDelivery'
  ) THEN
    INSERT INTO "NotificationDelivery" (
      "id", "userId", "campaignKey", "dedupeKey", "variant", "title", "body", "href", "context", "sentAt", "createdAt"
    )
    SELECT
      d."id",
      d."userId",
      'hot_search_digest',
      'hot_search_digest:' || d."userId" || ':' || d."slotKey",
      'treatment',
      'Есть срочная игра рядом',
      'Перенесено из HotSearchDigestDelivery',
      '/discover?view=hot',
      jsonb_build_object('slotKey', d."slotKey", 'searchIds', d."searchIds", 'migrated', true),
      d."createdAt",
      d."createdAt"
    FROM "HotSearchDigestDelivery" d
    WHERE EXISTS (SELECT 1 FROM "User" u WHERE u."id" = d."userId")
    ON CONFLICT ("dedupeKey") DO NOTHING;

    DROP TABLE "HotSearchDigestDelivery";
  END IF;
END
$$;

COMMIT;
