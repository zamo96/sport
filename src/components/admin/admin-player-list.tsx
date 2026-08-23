"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useState } from "react";
import { AlertCircle, ChevronLeft, ChevronRight, Search, ShieldOff, Users2 } from "lucide-react";

import { getDistrictLabel, SPORT_LABELS } from "@/lib/constants";
import { Avatar } from "@/components/ui/avatar";
import type { AdminAccountStatus, AdminPlayer, AdminPlayerPagination } from "@/components/admin/player-types";

type ListResponse = {
  items: AdminPlayer[];
  pagination: AdminPlayerPagination;
};

export function AdminPlayerList({
  initialQuery,
  initialStatus,
  initialPage
}: {
  initialQuery: string;
  initialStatus: "all" | AdminAccountStatus;
  initialPage: number;
}) {
  const router = useRouter();
  const [queryInput, setQueryInput] = useState(initialQuery);
  const [query, setQuery] = useState(initialQuery);
  const [status, setStatus] = useState(initialStatus);
  const [page, setPage] = useState(initialPage);
  const [data, setData] = useState<ListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    const params = new URLSearchParams({ page: String(page), limit: "12" });
    if (query) params.set("q", query);
    if (status !== "all") params.set("status", status);

    setLoading(true);
    setError(null);

    fetch(`/api/admin/players?${params.toString()}`, { signal: controller.signal })
      .then(async (response) => {
        const payload = (await response.json()) as ListResponse & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? "Не удалось загрузить игроков");
        return payload;
      })
      .then(setData)
      .catch((requestError: unknown) => {
        if (requestError instanceof DOMException && requestError.name === "AbortError") return;
        setError(requestError instanceof Error ? requestError.message : "Не удалось загрузить игроков");
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    const nextParams = new URLSearchParams();
    if (query) nextParams.set("q", query);
    if (status !== "all") nextParams.set("status", status);
    if (page > 1) nextParams.set("page", String(page));
    router.replace(`/admin/players${nextParams.size ? `?${nextParams.toString()}` : ""}`, { scroll: false });

    return () => controller.abort();
  }, [page, query, router, status]);

  function handleSearch(event: FormEvent) {
    event.preventDefault();
    setPage(1);
    setQuery(queryInput.trim());
  }

  const pagination = data?.pagination;

  return (
    <div className="space-y-5">
      <section className="rounded-lg border border-black/10 bg-white p-4 shadow-[0_10px_30px_rgba(17,38,29,0.06)]">
        <form onSubmit={handleSearch} className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_13rem_auto]">
          <label className="relative block">
            <span className="sr-only">Поиск игроков</span>
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/40" />
            <input
              value={queryInput}
              onChange={(event) => setQueryInput(event.target.value)}
              placeholder="Имя, email, ID, город или район"
              className="h-12 w-full rounded-lg border border-black/10 bg-[#fbfaf6] pl-10 pr-3 text-sm font-medium text-ink outline-none transition focus:border-court"
            />
          </label>
          <label>
            <span className="sr-only">Статус аккаунта</span>
            <select
              value={status}
              onChange={(event) => {
                setStatus(event.target.value as "all" | AdminAccountStatus);
                setPage(1);
              }}
              className="h-12 w-full rounded-lg border border-black/10 bg-[#fbfaf6] px-3 text-sm font-semibold text-ink outline-none focus:border-court"
            >
              <option value="all">Все статусы</option>
              <option value="active">Активные</option>
              <option value="deactivated">Деактивированные</option>
            </select>
          </label>
          <button className="h-12 rounded-lg bg-ink px-6 text-sm font-semibold text-white">Найти</button>
        </form>
      </section>

      <div className="flex flex-wrap items-center justify-between gap-3 text-sm text-ink/60">
        <div>{pagination ? `Найдено: ${pagination.total.toLocaleString("ru-RU")}` : "Загрузка списка…"}</div>
        {loading && data ? <div className="font-semibold text-court">Обновляем…</div> : null}
      </div>

      {error ? (
        <StatePanel icon={<AlertCircle className="h-6 w-6" />} title="Не удалось загрузить игроков" detail={error} tone="danger" />
      ) : loading && !data ? (
        <LoadingCards />
      ) : data && data.items.length === 0 ? (
        <StatePanel
          icon={<Users2 className="h-6 w-6" />}
          title="Игроки не найдены"
          detail="Измените поисковый запрос или фильтр статуса."
        />
      ) : (
        <div className={`grid gap-4 md:grid-cols-2 xl:grid-cols-3 ${loading ? "opacity-60" : ""}`} aria-busy={loading}>
          {data?.items.map((player) => <PlayerCard key={player.id} player={player} />)}
        </div>
      )}

      {pagination && pagination.totalPages > 1 ? (
        <nav className="flex items-center justify-center gap-3" aria-label="Пагинация игроков">
          <button
            type="button"
            disabled={loading || pagination.page <= 1}
            onClick={() => setPage((current) => Math.max(1, current - 1))}
            className="inline-flex h-11 items-center gap-2 rounded-lg border border-black/10 bg-white px-4 text-sm font-semibold text-ink disabled:opacity-40"
          >
            <ChevronLeft className="h-4 w-4" /> Назад
          </button>
          <span className="min-w-24 text-center text-sm font-semibold text-ink">
            {pagination.page} из {pagination.totalPages}
          </span>
          <button
            type="button"
            disabled={loading || pagination.page >= pagination.totalPages}
            onClick={() => setPage((current) => current + 1)}
            className="inline-flex h-11 items-center gap-2 rounded-lg border border-black/10 bg-white px-4 text-sm font-semibold text-ink disabled:opacity-40"
          >
            Вперёд <ChevronRight className="h-4 w-4" />
          </button>
        </nav>
      ) : null}
    </div>
  );
}

function PlayerCard({ player }: { player: AdminPlayer }) {
  const location = [player.city, getDistrictLabel(player.district) ?? player.district].filter(Boolean).join(" · ");

  return (
    <article className="flex h-full flex-col rounded-lg border border-black/10 bg-white p-4 shadow-[0_10px_30px_rgba(17,38,29,0.06)]">
      <div className="flex items-start gap-3">
        <Avatar src={player.avatarUrl} alt={player.name ?? player.email} size="md" className="shrink-0" />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <h2 className="truncate text-base font-bold text-ink">{player.name ?? "Без имени"}</h2>
              <div className="truncate text-xs text-ink/55">{player.email}</div>
            </div>
            <StatusBadge status={player.accountStatus} />
          </div>
          <div className="mt-2 truncate text-xs text-ink/55">{location || "Локация не указана"}</div>
        </div>
      </div>

      <div className="mt-4 flex flex-wrap gap-1.5">
        {player.preferredSports.length > 0 ? (
          player.preferredSports.slice(0, 4).map((sport) => (
            <span key={sport} className="rounded-full bg-cream px-2.5 py-1 text-xs font-semibold text-ink/70">
              {SPORT_LABELS[sport]}
              {typeof player.sportLevels[sport] === "number" ? ` · ${player.sportLevels[sport]}` : ""}
            </span>
          ))
        ) : (
          <span className="text-xs text-ink/45">Виды спорта не выбраны</span>
        )}
      </div>

      <dl className="mt-4 grid grid-cols-2 gap-2 text-xs">
        <Meta label="Активность" value={formatDate(player.lastActiveAt)} />
        <Meta label="Регистрация" value={formatDate(player.createdAt)} />
        <Meta label="Профиль" value={player.onboardingCompleted ? "Заполнен" : "Черновик"} />
        <Meta label="Поиск игры" value={player.isLookingForGame ? "Включён" : "Выключен"} />
      </dl>

      <Link
        href={`/admin/players/${player.id}`}
        className="mt-4 inline-flex h-11 items-center justify-center rounded-lg bg-ink px-4 text-sm font-semibold text-white"
      >
        Открыть карточку
      </Link>
    </article>
  );
}

function StatusBadge({ status }: { status: AdminAccountStatus }) {
  return status === "active" ? (
    <span className="shrink-0 rounded-full bg-emerald-100 px-2.5 py-1 text-[11px] font-bold text-emerald-700">Активен</span>
  ) : (
    <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-red-100 px-2.5 py-1 text-[11px] font-bold text-red-700">
      <ShieldOff className="h-3 w-3" /> Выключен
    </span>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md bg-[#fbfaf6] p-2.5">
      <dt className="text-ink/45">{label}</dt>
      <dd className="mt-1 font-semibold text-ink">{value}</dd>
    </div>
  );
}

function StatePanel({
  icon,
  title,
  detail,
  tone = "default"
}: {
  icon: React.ReactNode;
  title: string;
  detail: string;
  tone?: "default" | "danger";
}) {
  return (
    <div className={`rounded-lg border p-8 text-center ${tone === "danger" ? "border-red-200 bg-red-50 text-red-700" : "border-black/10 bg-white text-ink"}`}>
      <div className="mx-auto flex justify-center">{icon}</div>
      <div className="mt-3 font-bold">{title}</div>
      <div className="mt-1 text-sm opacity-70">{detail}</div>
    </div>
  );
}

function LoadingCards() {
  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3" aria-label="Загрузка игроков">
      {Array.from({ length: 6 }, (_, index) => (
        <div key={index} className="h-72 animate-pulse rounded-lg border border-black/5 bg-white/70" />
      ))}
    </div>
  );
}

function formatDate(value: string | null) {
  if (!value) return "Нет данных";
  return new Intl.DateTimeFormat("ru-RU", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(value));
}
