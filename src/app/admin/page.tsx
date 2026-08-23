import Link from "next/link";
import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import {
  Activity,
  AlertTriangle,
  BarChart3,
  Bell,
  Building2,
  Clock3,
  Database,
  GitBranch,
  LockKeyhole,
  MessageCircle,
  RefreshCw,
  Search,
  ShieldCheck,
  Trophy,
  Users2
} from "lucide-react";

import { getAdminAccessState } from "@/lib/admin";
import {
  getAdminDashboardData,
  type AdminDailyActivity,
  type AdminOperationalEvent,
  type AdminPlayerRoadmap,
  type AdminTimelineItem
} from "@/server/admin-dashboard";

export const dynamic = "force-dynamic";

export default async function AdminPage({
  searchParams
}: {
  searchParams?: { player?: string | string[] };
}) {
  const access = await getAdminAccessState();
  const playerQuery = Array.isArray(searchParams?.player) ? searchParams?.player[0] ?? "" : searchParams?.player ?? "";

  if (!access.user) {
    redirect(`/auth?continue=${encodeURIComponent("/admin")}&step=email`);
  }

  if (!access.configured || !access.isAdmin) {
    return <AdminAccessDenied configured={access.configured} email={access.user.email} />;
  }

  const dashboard = await getAdminDashboardData({ playerQuery });

  return (
    <main className="min-h-screen bg-[#f7f5ef] px-4 py-6 text-ink">
      <div className="mx-auto w-full max-w-7xl space-y-5">
        <header className="flex flex-col gap-4 rounded-lg border border-black/10 bg-white px-5 py-4 shadow-[0_10px_30px_rgba(17,38,29,0.08)] md:flex-row md:items-center md:justify-between">
          <div>
            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.22em] text-court">
              <ShieldCheck className="h-4 w-4" />
              Admin
            </div>
            <h1 className="mt-2 text-2xl font-bold leading-tight text-ink md:text-3xl">Операционная панель TennisSearch</h1>
            <p className="mt-2 max-w-2xl text-sm leading-6 text-ink/65">
              Пользователи, активность, ошибки интеграций и технические журналы из текущей базы.
            </p>
          </div>
          <div className="flex flex-col gap-2 text-sm text-ink/65 md:items-end">
            <div className="flex flex-col gap-2 sm:flex-row">
              <Link
                href="/admin/players"
                className="inline-flex h-11 items-center justify-center gap-2 rounded-lg bg-ink px-4 font-semibold text-white"
              >
                <Users2 className="h-4 w-4" />
                Модерация игроков
              </Link>
              <Link
                href="/admin/clubs"
                className="inline-flex h-11 items-center justify-center gap-2 rounded-lg bg-court px-4 font-semibold text-white"
              >
                <Building2 className="h-4 w-4" />
                Модерация клубов
              </Link>
            </div>
            <div className="inline-flex items-center gap-2 rounded-md bg-cream px-3 py-2 font-semibold text-ink">
              <Clock3 className="h-4 w-4" />
              {formatDateTime(dashboard.generatedAt)}
            </div>
            <div>{access.user.email}</div>
          </div>
        </header>

        <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard icon={<Users2 className="h-5 w-5" />} label="Пользователи" value={dashboard.metrics.usersTotal} helper={`${dashboard.metrics.usersActive24h} активны за 24ч`} />
          <MetricCard icon={<Activity className="h-5 w-5" />} label="Активность" value={dashboard.metrics.messages24h + dashboard.metrics.swipes24h} helper={`${dashboard.metrics.messages24h} сообщений, ${dashboard.metrics.swipes24h} свайпов`} />
          <MetricCard icon={<Search className="h-5 w-5" />} label="Активные поиски" value={dashboard.metrics.activeGameSearches} helper={`${dashboard.metrics.activeHotSearches} срочных`} />
          <MetricCard icon={<AlertTriangle className="h-5 w-5" />} label="Ошибки 24ч" value={dashboard.metrics.operationalErrors24h} helper={`${dashboard.metrics.reportsPending} отчетов ждут проверки`} tone={dashboard.metrics.operationalErrors24h > 0 ? "danger" : "default"} />
        </section>

        <Panel title="Активность по дням" icon={<BarChart3 className="h-5 w-5" />}>
          <DailyActivity days={dashboard.dailyActivity} />
        </Panel>

        <section className="grid gap-5 xl:grid-cols-[1.1fr_0.9fr]">
          <Panel title="Состояние продукта" icon={<Database className="h-5 w-5" />}>
            <div className="grid gap-3 md:grid-cols-3">
              <CompactStat label="Верифицированы" value={dashboard.metrics.usersVerified} helper={`${dashboard.metrics.usersOnboarded} с онбордингом`} />
              <CompactStat label="Новые за 7 дней" value={dashboard.metrics.usersNew7d} helper={`${dashboard.metrics.usersNew24h} за 24ч`} />
              <CompactStat label="Сессии" value={dashboard.metrics.activeSessions} helper={`${dashboard.metrics.usersActive7d} активны за 7д`} />
              <CompactStat label="Мэтчи" value={dashboard.metrics.activeMatches} helper="active status" />
              <CompactStat label="Предложения" value={dashboard.metrics.pendingGameRequests} helper="pending game requests" />
              <CompactStat label="Auth codes" value={dashboard.authCodeStats.created24h} helper={`${dashboard.authCodeStats.consumed24h} использованы за 24ч`} />
            </div>
            <div className="mt-4 grid gap-3 md:grid-cols-2">
              <StatusList title="GameSearch" counts={dashboard.searchStatusCounts} />
              <StatusList title="GameRequest" counts={dashboard.requestStatusCounts} />
            </div>
          </Panel>

          <Panel title="Пользователи онлайн" icon={<Users2 className="h-5 w-5" />}>
            <div className="divide-y divide-black/10">
              {dashboard.recentUsers.map((user) => (
                <div key={user.id} className="grid gap-2 py-3 md:grid-cols-[minmax(0,1fr)_auto] md:items-center">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-bold text-ink">{user.name ?? user.email}</div>
                    <div className="truncate text-xs text-ink/55">{user.email}</div>
                    <div className="mt-1 text-xs text-ink/55">{[user.city, user.district].filter(Boolean).join(" · ") || "Локация не указана"}</div>
                  </div>
                  <div className="flex flex-wrap gap-2 md:justify-end">
                    <Badge tone={user.isVerified ? "success" : "muted"}>{user.isVerified ? "verified" : "unverified"}</Badge>
                    <Badge tone={user.onboardingCompleted ? "success" : "warning"}>{user.onboardingCompleted ? "onboarded" : "draft"}</Badge>
                    <Badge tone={isRecent(user.lastActiveAt) ? "success" : "muted"}>{formatRelative(user.lastActiveAt)}</Badge>
                  </div>
                </div>
              ))}
            </div>
          </Panel>
        </section>

        <Panel title="Поиск игроков и user roadmap" icon={<GitBranch className="h-5 w-5" />}>
          <PlayerRoadmaps players={dashboard.playerRoadmaps} query={dashboard.playerQuery} />
        </Panel>

        <section className="grid gap-5 xl:grid-cols-[0.95fr_1.05fr]">
          <Panel title="Активность пользователей" icon={<Activity className="h-5 w-5" />}>
            <Timeline items={dashboard.recentActivity} />
          </Panel>

          <Panel title="Логи и ошибки" icon={<AlertTriangle className="h-5 w-5" />}>
            <OperationalEvents events={dashboard.operationalEvents} />
            <div className="mt-4 rounded-lg border border-dashed border-black/15 bg-white/70 p-3 text-sm leading-6 text-ink/65">
              Общий request/error log пока не сохраняется в базе. Этот экран показывает ошибки из maintenance, проверки сайтов,
              push-устройств и auth codes.
            </div>
          </Panel>
        </section>

        <Panel title="Maintenance runs" icon={<RefreshCw className="h-5 w-5" />}>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] border-collapse text-left text-sm">
              <thead>
                <tr className="border-b border-black/10 text-xs uppercase tracking-[0.16em] text-ink/45">
                  <th className="py-2 pr-3 font-semibold">Run</th>
                  <th className="py-2 pr-3 font-semibold">Статус</th>
                  <th className="py-2 pr-3 font-semibold">Город</th>
                  <th className="py-2 pr-3 font-semibold">Начало</th>
                  <th className="py-2 pr-3 font-semibold">Изменения</th>
                  <th className="py-2 pr-3 font-semibold">Ошибки</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-black/10">
                {dashboard.maintenanceRuns.map((run) => (
                  <tr key={run.id}>
                    <td className="py-3 pr-3">
                      <div className="font-semibold text-ink">{run.sourceType}</div>
                      <div className="font-mono text-xs text-ink/45">{run.id}</div>
                    </td>
                    <td className="py-3 pr-3"><Badge tone={run.status === "failed" ? "danger" : run.status === "running" ? "warning" : "success"}>{run.status}</Badge></td>
                    <td className="py-3 pr-3 text-ink/70">{run.city}</td>
                    <td className="py-3 pr-3 text-ink/70">{formatDateTime(run.startedAt)}</td>
                    <td className="py-3 pr-3 text-ink/70">{run.createdCount} new · {run.updatedCount} upd · {run.proposedCount} review</td>
                    <td className="py-3 pr-3 text-ink/70">{run.errorMessage ?? `${run.websiteFailedCount} website failed`}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Panel>
      </div>
    </main>
  );
}

function AdminAccessDenied({ configured, email }: { configured: boolean; email: string }) {
  return (
    <main className="min-h-screen bg-[#f7f5ef] px-4 py-6 text-ink">
      <div className="mx-auto max-w-xl rounded-lg border border-black/10 bg-white p-5 shadow-[0_10px_30px_rgba(17,38,29,0.08)]">
        <div className="flex items-center gap-2 text-sm font-semibold text-red-600">
          <LockKeyhole className="h-5 w-5" />
          Нет доступа
        </div>
        <h1 className="mt-3 text-2xl font-bold text-ink">Админка закрыта для этого аккаунта</h1>
        <p className="mt-3 text-sm leading-6 text-ink/65">
          Текущий email: <span className="font-semibold text-ink">{email}</span>
        </p>
        <p className="mt-2 text-sm leading-6 text-ink/65">
          {configured
            ? "Добавьте этот email в ADMIN_EMAILS, если аккаунт должен иметь доступ."
            : "Переменная ADMIN_EMAILS или ADMIN_EMAIL не настроена, поэтому доступ закрыт для всех."}
        </p>
        <Link href="/discover" className="mt-4 inline-flex rounded-md bg-ink px-4 py-3 text-sm font-semibold text-white">
          Вернуться в приложение
        </Link>
      </div>
    </main>
  );
}

function Panel({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) {
  return (
    <section className="rounded-lg border border-black/10 bg-white p-4 shadow-[0_10px_30px_rgba(17,38,29,0.06)]">
      <div className="mb-3 flex items-center gap-2 text-base font-bold text-ink">
        <span className="text-court">{icon}</span>
        {title}
      </div>
      {children}
    </section>
  );
}

function MetricCard({
  icon,
  label,
  value,
  helper,
  tone = "default"
}: {
  icon: ReactNode;
  label: string;
  value: number;
  helper: string;
  tone?: "default" | "danger";
}) {
  return (
    <div className={`rounded-lg border p-4 shadow-[0_10px_30px_rgba(17,38,29,0.06)] ${tone === "danger" ? "border-red-200 bg-red-50" : "border-black/10 bg-white"}`}>
      <div className="flex items-center justify-between gap-3">
        <div className="text-sm font-semibold text-ink/60">{label}</div>
        <div className={tone === "danger" ? "text-red-600" : "text-court"}>{icon}</div>
      </div>
      <div className="mt-3 text-3xl font-bold leading-none text-ink">{value.toLocaleString("ru-RU")}</div>
      <div className="mt-2 text-xs leading-5 text-ink/55">{helper}</div>
    </div>
  );
}

function CompactStat({ label, value, helper }: { label: string; value: number; helper: string }) {
  return (
    <div className="rounded-lg border border-black/10 bg-[#fbfaf6] p-3">
      <div className="text-xs font-semibold uppercase tracking-[0.16em] text-ink/45">{label}</div>
      <div className="mt-2 text-2xl font-bold text-ink">{value.toLocaleString("ru-RU")}</div>
      <div className="mt-1 text-xs text-ink/55">{helper}</div>
    </div>
  );
}

function StatusList({ title, counts }: { title: string; counts: Record<string, number> }) {
  return (
    <div className="rounded-lg border border-black/10 bg-[#fbfaf6] p-3">
      <div className="mb-2 text-xs font-semibold uppercase tracking-[0.16em] text-ink/45">{title}</div>
      <div className="grid gap-2">
        {Object.entries(counts).map(([status, count]) => (
          <div key={status} className="flex items-center justify-between gap-3 text-sm">
            <span className="text-ink/65">{status}</span>
            <span className="font-bold text-ink">{count.toLocaleString("ru-RU")}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function DailyActivity({ days }: { days: AdminDailyActivity[] }) {
  const maxActivity = Math.max(...days.map((day) => day.total), 1);

  return (
    <div className="space-y-3">
      <div className="grid gap-2 text-xs font-semibold uppercase tracking-[0.12em] text-ink/45 md:grid-cols-[6rem_minmax(0,1fr)_22rem]">
        <div>День</div>
        <div>Действия</div>
        <div className="hidden md:block">Состав</div>
      </div>
      <div className="space-y-2">
        {days.map((day) => {
          const width = day.total > 0 ? Math.max(4, Math.round((day.total / maxActivity) * 100)) : 0;

          return (
            <div key={day.day} className="grid gap-2 rounded-lg border border-black/10 bg-[#fbfaf6] p-3 md:grid-cols-[6rem_minmax(0,1fr)_22rem] md:items-center">
              <div>
                <div className="text-sm font-bold text-ink">{day.label}</div>
                <div className="font-mono text-[11px] text-ink/45">{day.day.slice(5)}</div>
              </div>
              <div className="min-w-0">
                <div className="h-3 overflow-hidden rounded-full bg-black/5">
                  <div className="h-full rounded-full bg-court" style={{ width: `${width}%` }} />
                </div>
                <div className="mt-2 flex flex-wrap gap-1.5 text-xs">
                  <Badge tone="muted">total {day.total}</Badge>
                  <Badge tone="success">новые {day.newUsers}</Badge>
                  <Badge tone="muted">last seen {day.lastSeenUsers}</Badge>
                  {day.errors > 0 ? <Badge tone="danger">ошибки {day.errors}</Badge> : null}
                </div>
              </div>
              <div className="grid grid-cols-3 gap-2 text-xs text-ink/65 md:grid-cols-5">
                <MiniCount label="поиски" value={day.searches} />
                <MiniCount label="предл." value={day.gameRequests} />
                <MiniCount label="мэтчи" value={day.matches} />
                <MiniCount label="сообщ." value={day.messages} />
                <MiniCount label="свайпы" value={day.swipes} />
              </div>
            </div>
          );
        })}
      </div>
      <div className="text-xs leading-5 text-ink/50">
        `last seen` основан на текущем `User.lastActiveAt`, поэтому это последняя активность пользователя, а не полный исторический журнал визитов.
      </div>
    </div>
  );
}

function PlayerRoadmaps({ players, query }: { players: AdminPlayerRoadmap[]; query: string }) {
  return (
    <div className="space-y-4">
      <form action="/admin" className="grid gap-2 md:grid-cols-[minmax(0,1fr)_auto_auto]">
        <label className="relative block">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/40" />
          <input
            name="player"
            defaultValue={query}
            placeholder="Email, имя, id, город или район"
            className="h-12 w-full rounded-lg border border-black/10 bg-[#fbfaf6] pl-10 pr-3 text-sm font-medium text-ink outline-none transition focus:border-court"
          />
        </label>
        <button className="inline-flex h-12 items-center justify-center rounded-lg bg-ink px-5 text-sm font-semibold text-white">
          Найти
        </button>
        {query ? (
          <Link href="/admin" className="inline-flex h-12 items-center justify-center rounded-lg bg-black/5 px-5 text-sm font-semibold text-ink">
            Сбросить
          </Link>
        ) : null}
      </form>

      <div className="grid gap-3 xl:grid-cols-2">
        {players.length === 0 ? (
          <div className="rounded-lg bg-[#fbfaf6] p-4 text-sm text-ink/60">Игроки не найдены.</div>
        ) : (
          players.map((player) => <PlayerRoadmapCard key={player.id} player={player} />)
        )}
      </div>
    </div>
  );
}

function PlayerRoadmapCard({ player }: { player: AdminPlayerRoadmap }) {
  const proposalTotal = player.proposalsSent + player.proposalsReceived;
  const sports = player.preferredSports.length > 0 ? player.preferredSports.slice(0, 3).join(", ") : "sports empty";

  return (
    <article className="rounded-lg border border-black/10 bg-[#fbfaf6] p-4">
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
        <div className="min-w-0">
          <div className="truncate text-base font-bold text-ink">{player.name ?? player.email}</div>
          <div className="mt-1 truncate text-xs text-ink/55">{player.email}</div>
          <div className="mt-1 text-xs text-ink/55">
            {[player.city, player.district, sports].filter(Boolean).join(" · ")}
          </div>
        </div>
        <div className="flex flex-wrap gap-2 md:justify-end">
          <Badge tone={player.isVerified ? "success" : "muted"}>{player.isVerified ? "verified" : "unverified"}</Badge>
          <Badge tone={player.onboardingCompleted ? "success" : "warning"}>{player.onboardingCompleted ? "onboarded" : "draft"}</Badge>
          <Badge tone={isRecent(player.lastActiveAt) ? "success" : "muted"}>{formatRelative(player.lastActiveAt)}</Badge>
        </div>
      </div>

      <div className="relative mt-4 space-y-3 pl-7">
        <div className="absolute bottom-3 left-[0.6rem] top-2 w-px bg-court/35" />
        <RoadmapNode
          label="Профиль"
          value={player.onboardingCompleted ? "готов" : "черновик"}
          detail={`создан ${formatDate(player.createdAt)}`}
          tone={player.onboardingCompleted ? "success" : "warning"}
        />
        <RoadmapNode
          label="Мэтчи"
          value={`+${player.matches7d} за 7д`}
          detail={`${player.matchesTotal} всего`}
          tone={player.matches7d > 0 ? "success" : "muted"}
        />
        <RoadmapNode
          label="Предложения"
          value={`${proposalTotal} всего`}
          detail={`sent ${player.proposalsSent} · recv ${player.proposalsReceived} · pending ${player.proposalsPending}`}
          tone={player.proposalsDeclined > 0 ? "danger" : proposalTotal > 0 ? "success" : "muted"}
        />
        <div className="ml-3 grid gap-2 rounded-lg border border-black/10 bg-white p-3 text-xs md:grid-cols-4">
          <MiniCount label="accepted" value={player.proposalsAccepted} />
          <MiniCount label="declined" value={player.proposalsDeclined} tone={player.proposalsDeclined > 0 ? "danger" : "muted"} />
          <MiniCount label="canceled" value={player.proposalsCanceled} />
          <MiniCount label="pending" value={player.proposalsPending} tone={player.proposalsPending > 0 ? "warning" : "muted"} />
        </div>
        <RoadmapNode
          label="Поиски и чат"
          value={`${player.searchesActive} active`}
          detail={`${player.searchesTotal} поисков · ${player.messages7d} сообщений за 7д`}
          tone={player.searchesActive > 0 ? "success" : "muted"}
        />
      </div>
    </article>
  );
}

function RoadmapNode({
  label,
  value,
  detail,
  tone = "muted"
}: {
  label: string;
  value: string;
  detail: string;
  tone?: "success" | "warning" | "danger" | "muted";
}) {
  const dotClassName =
    tone === "success"
      ? "border-emerald-300 bg-emerald-100"
      : tone === "warning"
        ? "border-amber-300 bg-amber-100"
        : tone === "danger"
          ? "border-red-300 bg-red-100"
          : "border-black/15 bg-white";

  return (
    <div className="relative rounded-lg border border-black/10 bg-white p-3">
      <span className={`absolute -left-[1.85rem] top-3 h-4 w-4 rounded-full border-2 ${dotClassName}`} />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="text-sm font-bold text-ink">{label}</div>
        <Badge tone={tone}>{value}</Badge>
      </div>
      <div className="mt-1 text-xs leading-5 text-ink/55">{detail}</div>
    </div>
  );
}

function MiniCount({ label, value, tone = "muted" }: { label: string; value: number; tone?: "warning" | "danger" | "muted" }) {
  const className =
    tone === "danger"
      ? "bg-red-50 text-red-700"
      : tone === "warning"
        ? "bg-amber-50 text-amber-800"
        : "bg-black/[0.03] text-ink/65";

  return (
    <div className={`rounded-md px-2 py-1.5 ${className}`}>
      <div className="font-mono text-sm font-bold leading-none text-ink">{value.toLocaleString("ru-RU")}</div>
      <div className="mt-1 truncate text-[10px] font-semibold uppercase tracking-[0.12em]">{label}</div>
    </div>
  );
}

function Timeline({ items }: { items: AdminTimelineItem[] }) {
  if (items.length === 0) {
    return <div className="rounded-lg bg-[#fbfaf6] p-4 text-sm text-ink/60">Событий пока нет.</div>;
  }

  return (
    <div className="divide-y divide-black/10">
      {items.map((item) => (
        <div key={item.id} className="grid gap-2 py-3 md:grid-cols-[auto_minmax(0,1fr)_auto] md:items-start">
          <div className="text-court">{getTimelineIcon(item.kind)}</div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <div className="font-semibold text-ink">{item.title}</div>
              {item.actorName ? <Badge tone="muted">{item.actorName}</Badge> : null}
            </div>
            <div className="mt-1 truncate text-sm text-ink/60">{item.subtitle}</div>
          </div>
          <div className="text-xs font-semibold text-ink/45 md:text-right">{formatDateTime(item.occurredAt)}</div>
        </div>
      ))}
    </div>
  );
}

function OperationalEvents({ events }: { events: AdminOperationalEvent[] }) {
  if (events.length === 0) {
    return <div className="rounded-lg bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">Критичных событий не найдено.</div>;
  }

  return (
    <div className="divide-y divide-black/10">
      {events.map((event) => (
        <div key={event.id} className="grid gap-2 py-3 md:grid-cols-[auto_minmax(0,1fr)_auto] md:items-start">
          <div className={event.severity === "error" ? "text-red-600" : event.severity === "warning" ? "text-amber-600" : "text-court"}>
            {event.source === "push" ? <Bell className="h-5 w-5" /> : <AlertTriangle className="h-5 w-5" />}
          </div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <div className="font-semibold text-ink">{event.title}</div>
              <Badge tone={event.severity === "error" ? "danger" : event.severity === "warning" ? "warning" : "muted"}>{event.source}</Badge>
            </div>
            <div className="mt-1 text-sm leading-6 text-ink/60">{event.message}</div>
          </div>
          <div className="text-xs font-semibold text-ink/45 md:text-right">{formatDateTime(event.occurredAt)}</div>
        </div>
      ))}
    </div>
  );
}

function Badge({ children, tone = "muted" }: { children: ReactNode; tone?: "success" | "warning" | "danger" | "muted" }) {
  const className =
    tone === "success"
      ? "bg-emerald-100 text-emerald-800"
      : tone === "warning"
        ? "bg-amber-100 text-amber-800"
        : tone === "danger"
          ? "bg-red-100 text-red-700"
          : "bg-black/5 text-ink/65";

  return <span className={`inline-flex rounded-md px-2 py-1 text-xs font-semibold ${className}`}>{children}</span>;
}

function getTimelineIcon(kind: AdminTimelineItem["kind"]) {
  switch (kind) {
    case "user":
      return <Users2 className="h-5 w-5" />;
    case "session":
      return <ShieldCheck className="h-5 w-5" />;
    case "search":
      return <Search className="h-5 w-5" />;
    case "request":
      return <Trophy className="h-5 w-5" />;
    case "message":
      return <MessageCircle className="h-5 w-5" />;
    case "report":
      return <AlertTriangle className="h-5 w-5" />;
    default:
      return <Activity className="h-5 w-5" />;
  }
}

function isRecent(value: Date | null) {
  return Boolean(value && Date.now() - value.getTime() <= 15 * 60 * 1000);
}

function formatRelative(value: Date | null) {
  if (!value) {
    return "no activity";
  }

  const diffMinutes = Math.max(0, Math.round((Date.now() - value.getTime()) / 60000));

  if (diffMinutes <= 5) {
    return "online";
  }

  if (diffMinutes < 60) {
    return `${diffMinutes} мин назад`;
  }

  const diffHours = Math.round(diffMinutes / 60);

  if (diffHours < 24) {
    return `${diffHours} ч назад`;
  }

  return value.toLocaleDateString("ru-RU");
}

function formatDateTime(value: Date) {
  return value.toLocaleString("ru-RU", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });
}

function formatDate(value: Date) {
  return value.toLocaleDateString("ru-RU", {
    day: "2-digit",
    month: "2-digit",
    year: "2-digit"
  });
}
