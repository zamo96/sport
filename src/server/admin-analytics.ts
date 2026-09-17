import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  ANALYTICS_EXPORT_LIMIT, ANALYTICS_PAGE_SIZE, analyticsEventLabel, analyticsPeriod, analyticsRate,
  buildAnalyticsFunnel, normalizeAnalyticsFilters,
  type AdminAnalyticsData, type AdminAnalyticsOptions, type AnalyticsFilters, type AnalyticsJournalItem
} from "@/lib/admin-analytics";

export type { AdminAnalyticsData, AdminAnalyticsOptions, AnalyticsJournalItem } from "@/lib/admin-analytics";

type Count = bigint | number;
const activeEventPredicate = Prisma.sql`e."type" NOT IN ('push_sent', 'push_converted', 'match_created', 'request_accepted', 'game_played')`;

// Current domain state is authoritative: reversals and disputed reports remove a game from conversion.
// Each invitation contributes only its own two participants; declined invitees are never inferred as players.
const playedCtes = Prisma.sql`
  valid_games AS (
    SELECT r."id", COALESCE(r."sharedRootId", r."id") AS "gameId", r."createdByUserId", r."matchedUserId",
      CASE WHEN r."outcome" IS NULL THEN root_game."outcomeUpdatedAt" ELSE r."outcomeUpdatedAt" END AS "playedAt"
    FROM "GameRequest" r
    LEFT JOIN "GameRequest" root_game ON root_game."id" = r."sharedRootId"
    LEFT JOIN "GameReport" report ON report."gameRequestId" = COALESCE(r."sharedRootId", r."id")
    LEFT JOIN "GameReport" own_report ON own_report."gameRequestId" = r."id"
    WHERE r."status" = 'accepted'
      AND (r."outcome" = 'played' OR (r."outcome" IS NULL AND root_game."status" = 'accepted' AND root_game."outcome" = 'played'))
      AND (CASE WHEN r."outcome" IS NULL THEN root_game."outcomeUpdatedAt" ELSE r."outcomeUpdatedAt" END) IS NOT NULL
      AND (report."status" IS NULL OR report."status" <> 'disputed')
      AND (own_report."status" IS NULL OR own_report."status" <> 'disputed')
  ),
  played_participants AS (
    SELECT "createdByUserId" AS "userId", "playedAt" FROM valid_games
    UNION ALL SELECT "matchedUserId" AS "userId", "playedAt" FROM valid_games
  ),
  first_games AS (SELECT "userId", MIN("playedAt") AS "playedAt" FROM played_participants GROUP BY "userId")
`;

function journalWhere(filters: AnalyticsFilters, period: { from: Date; to: Date }): Prisma.UserEventWhereInput {
  return {
    createdAt: { gte: period.from, lte: period.to },
    ...(filters.userId ? { userId: filters.userId } : {}),
    ...(filters.eventType ? { type: filters.eventType } : {})
  };
}
async function journalItems(where: Prisma.UserEventWhereInput, take: number, skip = 0): Promise<AnalyticsJournalItem[]> {
  const events = await prisma.userEvent.findMany({
    where, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take, skip,
    select: {
      id: true, userId: true, type: true, entityType: true, entityId: true, context: true, createdAt: true,
      user: { select: { name: true, email: true } }
    }
  });
  return events.map(({ user, ...event }) => ({ ...event, label: analyticsEventLabel(event.type), userName: user.name, userEmail: user.email }));
}

export async function getAdminAnalyticsExport(options: AdminAnalyticsOptions = {}) {
  const filters = normalizeAnalyticsFilters(options);
  const items = await journalItems(journalWhere(filters, analyticsPeriod(filters.days)), ANALYTICS_EXPORT_LIMIT + 1);
  return { items: items.slice(0, ANALYTICS_EXPORT_LIMIT), truncated: items.length > ANALYTICS_EXPORT_LIMIT };
}

export async function getAdminAnalyticsData(options: AdminAnalyticsOptions = {}): Promise<AdminAnalyticsData> {
  const generatedAt = new Date();
  const filters = normalizeAnalyticsFilters(options);
  const period = analyticsPeriod(filters.days, generatedAt);
  const { from, to } = period;
  const where = journalWhere(filters, period);
  const [totals, funnelRows, dailyRows, breakdown, coverageRows, journalTotal] = await Promise.all([
    prisma.$queryRaw<Array<{ newUsers: Count; activeUsers: Count; totalEvents: Count; playedUsers: Count; playedGames: Count }>>(Prisma.sql`
      WITH ${playedCtes}
      SELECT
        (SELECT COUNT(*) FROM "User" u WHERE u."createdAt" >= ${from} AND u."createdAt" <= ${to}) AS "newUsers",
        (SELECT COUNT(DISTINCT e."userId") FROM "UserEvent" e WHERE e."createdAt" >= ${from} AND e."createdAt" <= ${to} AND ${activeEventPredicate}) AS "activeUsers",
        (SELECT COUNT(*) FROM "UserEvent" e WHERE e."createdAt" >= ${from} AND e."createdAt" <= ${to}) AS "totalEvents",
        (SELECT COUNT(*) FROM first_games g JOIN "User" u ON u."id" = g."userId"
          WHERE u."createdAt" >= ${from} AND u."createdAt" <= ${to} AND g."playedAt" >= u."createdAt" AND g."playedAt" <= ${to}) AS "playedUsers",
        (SELECT COUNT(DISTINCT "gameId") FROM valid_games WHERE "playedAt" >= ${from} AND "playedAt" <= ${to}) AS "playedGames"
    `),
    prisma.$queryRaw<Array<{ registered: Count; profile: Count; intent: Count; accepted: Count; played: Count }>>(Prisma.sql`
      WITH ${playedCtes}, cohort AS (
        SELECT u."id", u."createdAt" FROM "User" u WHERE u."createdAt" >= ${from} AND u."createdAt" <= ${to}
      )
      SELECT COUNT(*) AS registered, COUNT(profile.at) AS profile, COUNT(intent.at) AS intent,
        COUNT(accepted.at) AS accepted,
        COUNT(*) FILTER (WHERE accepted.at IS NOT NULL AND g."playedAt" >= accepted.at AND g."playedAt" <= ${to}) AS played
      FROM cohort c
      LEFT JOIN LATERAL (
        SELECT MIN(e."createdAt") AS at FROM "UserEvent" e
        WHERE e."userId" = c."id" AND e."type" = 'profile_completed' AND e."createdAt" >= c."createdAt" AND e."createdAt" <= ${to}
      ) profile ON TRUE
      LEFT JOIN LATERAL (
        SELECT MIN(e."createdAt") AS at FROM "UserEvent" e
        WHERE e."userId" = c."id" AND e."createdAt" >= profile.at AND e."createdAt" <= ${to}
          AND (e."type" IN ('search_created', 'search_response', 'request_created')
            OR (e."type" = 'swipe' AND e."context"->>'action' IN ('like', 'superlike')))
      ) intent ON TRUE
      LEFT JOIN LATERAL (
        SELECT MIN(e."createdAt") AS at FROM "UserEvent" e
        WHERE e."userId" = c."id" AND e."type" = 'request_accepted' AND e."createdAt" >= intent.at AND e."createdAt" <= ${to}
      ) accepted ON TRUE
      LEFT JOIN first_games g ON g."userId" = c."id"
    `),
    prisma.$queryRaw<Array<{ day: string; registrations: Count; activeUsers: Count; events: Count; firstGames: Count }>>(Prisma.sql`
      WITH ${playedCtes}, days AS (
        SELECT generate_series(${from}::timestamp, ${to}::timestamp, interval '1 day')::date AS day
      ), registrations AS (
        SELECT u."createdAt"::date AS day, COUNT(*) AS total FROM "User" u
        WHERE u."createdAt" >= ${from} AND u."createdAt" <= ${to} GROUP BY 1
      ), activity AS (
        SELECT e."createdAt"::date AS day, COUNT(*) AS total, COUNT(DISTINCT e."userId") FILTER (WHERE ${activeEventPredicate}) AS users
        FROM "UserEvent" e WHERE e."createdAt" >= ${from} AND e."createdAt" <= ${to} GROUP BY 1
      ), games AS (
        SELECT "playedAt"::date AS day, COUNT(*) AS total FROM first_games
        WHERE "playedAt" >= ${from} AND "playedAt" <= ${to} GROUP BY 1
      )
      SELECT to_char(d.day, 'YYYY-MM-DD') AS day, COALESCE(r.total, 0) AS registrations,
        COALESCE(a.users, 0) AS "activeUsers", COALESCE(a.total, 0) AS events, COALESCE(g.total, 0) AS "firstGames"
      FROM days d LEFT JOIN registrations r ON r.day = d.day LEFT JOIN activity a ON a.day = d.day LEFT JOIN games g ON g.day = d.day
      ORDER BY d.day
    `),
    prisma.$queryRaw<Array<{ type: string; count: Count; users: Count }>>(Prisma.sql`
      SELECT "type", COUNT(*) AS count, COUNT(DISTINCT "userId") AS users FROM "UserEvent"
      WHERE "createdAt" >= ${from} AND "createdAt" <= ${to} GROUP BY "type" ORDER BY count DESC, "type" ASC
    `),
    prisma.$queryRaw<Array<{ firstEventAt: Date | null; firstFunnelEventAt: Date | null }>>(Prisma.sql`
      SELECT (SELECT "createdAt" FROM "UserEvent" ORDER BY "createdAt" ASC LIMIT 1) AS "firstEventAt",
        (SELECT MIN(first_type.at) FROM (
          SELECT (SELECT "createdAt" FROM "UserEvent" WHERE "type" = milestone.type ORDER BY "createdAt" ASC LIMIT 1) AS at
          FROM (VALUES ('registration_completed'), ('profile_completed'), ('request_created'), ('request_accepted')) milestone(type)
        ) first_type) AS "firstFunnelEventAt"
    `),
    prisma.userEvent.count({ where })
  ]);
  const totalPages = Math.max(1, Math.ceil(journalTotal / ANALYTICS_PAGE_SIZE));
  filters.page = Math.min(filters.page, totalPages);
  const items = await journalItems(where, ANALYTICS_PAGE_SIZE, (filters.page - 1) * ANALYTICS_PAGE_SIZE);
  const raw = totals[0];
  const newUsers = Number(raw?.newUsers ?? 0);
  const playedUsers = Number(raw?.playedUsers ?? 0);
  const funnel = funnelRows[0];
  return {
    generatedAt, filters, period,
    coverage: {
      firstEventAt: coverageRows[0]?.firstEventAt ?? null,
      firstFunnelEventAt: coverageRows[0]?.firstFunnelEventAt ?? null,
      notes: [
        "Период — календарные дни UTC, включая текущий неполный день. Когорта — аккаунты, созданные за выбранный период; недавние регистрации ещё не успели дойти до игры.",
        "Конверсия регистрации в игру рассчитана по текущим данным игр независимо от журнала. Игра считается сыгранной по отметке участника, при принятом предложении; спорные фотоотчёты исключены. Это не независимая проверка проведения игры.",
        "Воронка требует последовательных событий одного пользователя: профиль → действие → согласование → первая игра. Она может быть ниже прямой конверсии: предыдущие действия до начала сбора не восстановлены, часть пользователей получает приглашение без собственного поиска.",
        "Дата первого события — начало доступной истории, а не доказанная дата запуска сбора. Просмотры экранов собираются в веб-версии; серверные действия — для веб и iOS. Гостевые посещения и уход до регистрации не наблюдаются.",
        "Активные пользователи — уникальные пользователи с записанными действиями за период; отправка push, автоматическая конверсия push, мэтч и отметки принятия/проведения игры сами по себе активностью не считаются.",
        "Первая игра в динамике — первый действующий результат played пользователя за всю историю, попавший в этот день; один матч может быть первым у двух игроков. Отменённые результаты и споры меняют исторические показатели.",
        "Фильтры пользователя и события действуют только на журнал и CSV. Экспорт содержит до 10 000 последних событий; при превышении в файл добавляется предупреждение."
      ]
    },
    metrics: { newUsers, activeUsers: Number(raw?.activeUsers ?? 0), totalEvents: Number(raw?.totalEvents ?? 0), playedUsers,
      playedGames: Number(raw?.playedGames ?? 0), registrationToGameRate: analyticsRate(playedUsers, newUsers) },
    funnel: buildAnalyticsFunnel([funnel?.registered, funnel?.profile, funnel?.intent, funnel?.accepted, funnel?.played].map((count) => Number(count ?? 0))),
    daily: dailyRows.map((row) => ({ day: row.day, registrations: Number(row.registrations), activeUsers: Number(row.activeUsers), events: Number(row.events), firstGames: Number(row.firstGames) })),
    eventBreakdown: breakdown.map((row) => ({ type: row.type, label: analyticsEventLabel(row.type), count: Number(row.count), users: Number(row.users) })),
    journal: { items, total: journalTotal, page: filters.page, pageSize: ANALYTICS_PAGE_SIZE, totalPages }
  };
}
