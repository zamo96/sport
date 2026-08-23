"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useState } from "react";
import { AlertCircle, Building2, ChevronLeft, ChevronRight, CircleAlert, MapPin, Search } from "lucide-react";
import type { Sport } from "@prisma/client";

import type {
  AdminClubFilters,
  AdminClubPagination,
  AdminClubStatus,
  AdminClubSummary
} from "@/components/admin/club-types";
import { getDistrictLabel, SPORT_LABELS, SPORT_OPTIONS } from "@/lib/constants";

type ListResponse = {
  items: AdminClubSummary[];
  pagination: AdminClubPagination;
  filters: AdminClubFilters;
};

const statusOptions: Array<{ value: AdminClubStatus; label: string }> = [
  { value: "active", label: "Активные" },
  { value: "needs_review", label: "Нужна проверка" },
  { value: "hidden", label: "Скрытые" },
  { value: "archived", label: "Архивные" }
];

export function AdminClubList({
  initialQuery,
  initialStatus,
  initialCity,
  initialSport,
  initialSourceType,
  initialPage
}: {
  initialQuery: string;
  initialStatus: "all" | AdminClubStatus;
  initialCity: string;
  initialSport: "all" | Sport;
  initialSourceType: string;
  initialPage: number;
}) {
  const router = useRouter();
  const [queryInput, setQueryInput] = useState(initialQuery);
  const [query, setQuery] = useState(initialQuery);
  const [status, setStatus] = useState(initialStatus);
  const [city, setCity] = useState(initialCity);
  const [sport, setSport] = useState(initialSport);
  const [sourceType, setSourceType] = useState(initialSourceType);
  const [page, setPage] = useState(initialPage);
  const [data, setData] = useState<ListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    const params = new URLSearchParams({ page: String(page), limit: "12" });
    if (query) params.set("q", query);
    if (status !== "all") params.set("status", status);
    if (city !== "all") params.set("city", city);
    if (sport !== "all") params.set("sport", sport);
    if (sourceType !== "all") params.set("sourceType", sourceType);

    setLoading(true);
    setError(null);

    fetch(`/api/admin/clubs?${params.toString()}`, { signal: controller.signal })
      .then(async (response) => {
        const payload = (await response.json()) as ListResponse & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? "Не удалось загрузить клубы");
        return payload;
      })
      .then(setData)
      .catch((requestError: unknown) => {
        if (requestError instanceof DOMException && requestError.name === "AbortError") return;
        setError(requestError instanceof Error ? requestError.message : "Не удалось загрузить клубы");
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    const locationParams = new URLSearchParams();
    if (query) locationParams.set("q", query);
    if (status !== "all") locationParams.set("status", status);
    if (city !== "all") locationParams.set("city", city);
    if (sport !== "all") locationParams.set("sport", sport);
    if (sourceType !== "all") locationParams.set("sourceType", sourceType);
    if (page > 1) locationParams.set("page", String(page));
    router.replace(`/admin/clubs${locationParams.size ? `?${locationParams.toString()}` : ""}`, { scroll: false });

    return () => controller.abort();
  }, [city, page, query, router, sourceType, sport, status]);

  function handleSearch(event: FormEvent) {
    event.preventDefault();
    setPage(1);
    setQuery(queryInput.trim());
  }

  function changeFilter(setter: (value: string) => void, value: string) {
    setter(value);
    setPage(1);
  }

  const pagination = data?.pagination;
  const cities = withCurrent(data?.filters.cities ?? [], city);
  const sources = withCurrent(data?.filters.sourceTypes ?? [], sourceType);
  const sports = SPORT_OPTIONS;

  return (
    <div className="space-y-5">
      <section className="rounded-lg border border-black/10 bg-white p-4 shadow-[0_10px_30px_rgba(17,38,29,0.06)]">
        <form onSubmit={handleSearch} className="grid gap-3 lg:grid-cols-2 xl:grid-cols-[minmax(15rem,1fr)_11rem_11rem_11rem_12rem_auto]">
          <label className="relative block lg:col-span-2 xl:col-span-1">
            <span className="sr-only">Поиск клубов</span>
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/40" />
            <input
              value={queryInput}
              onChange={(event) => setQueryInput(event.target.value)}
              placeholder="Название, адрес или ID"
              className={inputClass("pl-10")}
            />
          </label>
          <FilterSelect label="Статус" value={status} onChange={(value) => changeFilter((next) => setStatus(next as typeof status), value)}>
            <option value="all">Все статусы</option>
            {statusOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </FilterSelect>
          <FilterSelect label="Город" value={city} onChange={(value) => changeFilter(setCity, value)}>
            <option value="all">Все города</option>
            {cities.map((value) => <option key={value} value={value}>{value}</option>)}
          </FilterSelect>
          <FilterSelect label="Вид спорта" value={sport} onChange={(value) => changeFilter((next) => setSport(next as typeof sport), value)}>
            <option value="all">Все виды спорта</option>
            {sports.map((value) => <option key={value} value={value}>{SPORT_LABELS[value]}</option>)}
          </FilterSelect>
          <FilterSelect label="Источник" value={sourceType} onChange={(value) => changeFilter(setSourceType, value)}>
            <option value="all">Все источники</option>
            {sources.map((value) => <option key={value} value={value}>{value}</option>)}
          </FilterSelect>
          <button className="h-12 rounded-lg bg-ink px-6 text-sm font-semibold text-white">Найти</button>
        </form>
      </section>

      <div className="flex flex-wrap items-center justify-between gap-3 text-sm text-ink/60">
        <div>{pagination ? `Найдено: ${pagination.total.toLocaleString("ru-RU")}` : "Загрузка списка…"}</div>
        {loading && data ? <div className="font-semibold text-court">Обновляем…</div> : null}
      </div>

      {error ? (
        <StatePanel icon={<AlertCircle className="h-6 w-6" />} title="Не удалось загрузить клубы" detail={error} tone="danger" />
      ) : loading && !data ? (
        <LoadingCards />
      ) : data && data.items.length === 0 ? (
        <StatePanel icon={<Building2 className="h-6 w-6" />} title="Клубы не найдены" detail="Измените поисковый запрос или один из фильтров." />
      ) : (
        <div className={`grid gap-4 md:grid-cols-2 xl:grid-cols-3 ${loading ? "opacity-60" : ""}`} aria-busy={loading}>
          {data?.items.map((club) => <ClubCard key={club.id} club={club} />)}
        </div>
      )}

      {pagination && pagination.totalPages > 1 ? (
        <nav className="flex items-center justify-center gap-3" aria-label="Пагинация клубов">
          <button type="button" disabled={loading || pagination.page <= 1} onClick={() => setPage((current) => Math.max(1, current - 1))} className={pagerClass}>
            <ChevronLeft className="h-4 w-4" /> Назад
          </button>
          <span className="min-w-24 text-center text-sm font-semibold text-ink">{pagination.page} из {pagination.totalPages}</span>
          <button type="button" disabled={loading || pagination.page >= pagination.totalPages} onClick={() => setPage((current) => current + 1)} className={pagerClass}>
            Вперёд <ChevronRight className="h-4 w-4" />
          </button>
        </nav>
      ) : null}
    </div>
  );
}

function ClubCard({ club }: { club: AdminClubSummary }) {
  const district = getDistrictLabel(club.district) ?? club.district;

  return (
    <article className="flex h-full flex-col overflow-hidden rounded-lg border border-black/10 bg-white shadow-[0_10px_30px_rgba(17,38,29,0.06)]">
      <div
        className="flex h-36 items-center justify-center bg-gradient-to-br from-mint to-cream bg-cover bg-center text-court"
        style={club.photoUrl ? { backgroundImage: `linear-gradient(rgba(17,38,29,.08),rgba(17,38,29,.08)),url(${JSON.stringify(club.photoUrl)})` } : undefined}
        role={club.photoUrl ? "img" : undefined}
        aria-label={club.photoUrl ? `Фотография клуба ${club.name}` : undefined}
      >
        {!club.photoUrl ? <Building2 className="h-10 w-10" /> : null}
      </div>
      <div className="flex flex-1 flex-col p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h2 className="truncate text-base font-bold text-ink">{club.name}</h2>
            <div className="mt-1 flex items-start gap-1 text-xs leading-5 text-ink/55">
              <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              <span>{[club.city, district, club.address].filter(Boolean).join(" · ")}</span>
            </div>
          </div>
          <StatusBadge status={club.status} />
        </div>

        {club.pendingProposalCount > 0 ? (
          <div className="mt-3 flex items-center gap-2 rounded-md bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
            <CircleAlert className="h-4 w-4 shrink-0" />
            {pluralizeProposals(club.pendingProposalCount)} ждут проверки
          </div>
        ) : null}

        <div className="mt-3 flex flex-wrap gap-1.5">
          {club.supportedSports.map((value) => (
            <span key={value} className="rounded-full bg-cream px-2.5 py-1 text-xs font-semibold text-ink/70">{SPORT_LABELS[value]}</span>
          ))}
        </div>

        <dl className="mt-4 grid grid-cols-2 gap-2 text-xs">
          <Meta label="Источник" value={club.sourceType} />
          <Meta label="Цена" value={club.priceRange || "Не указана"} />
          <Meta label="Рейтинг" value={club.rating == null ? "Нет данных" : club.rating.toLocaleString("ru-RU", { maximumFractionDigits: 1 })} />
          <Meta label="Обновлён" value={formatDate(club.updatedAt)} />
        </dl>

        <Link href={`/admin/clubs/${club.id}`} className="mt-4 inline-flex h-11 items-center justify-center rounded-lg bg-ink px-4 text-sm font-semibold text-white">
          Открыть клуб
        </Link>
      </div>
    </article>
  );
}

function StatusBadge({ status }: { status: AdminClubStatus }) {
  const styles: Record<AdminClubStatus, string> = {
    active: "bg-emerald-100 text-emerald-700",
    needs_review: "bg-amber-100 text-amber-800",
    hidden: "bg-slate-200 text-slate-700",
    archived: "bg-red-100 text-red-700"
  };
  const labels: Record<AdminClubStatus, string> = {
    active: "Активен",
    needs_review: "На проверке",
    hidden: "Скрыт",
    archived: "В архиве"
  };
  return <span className={`shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold ${styles[status]}`}>{labels[status]}</span>;
}

function FilterSelect({ label, value, onChange, children }: { label: string; value: string; onChange: (value: string) => void; children: React.ReactNode }) {
  return (
    <label>
      <span className="sr-only">{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value)} className={inputClass()}>{children}</select>
    </label>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return <div className="rounded-md bg-[#fbfaf6] p-2.5"><dt className="text-ink/45">{label}</dt><dd className="mt-1 truncate font-semibold text-ink">{value}</dd></div>;
}

function StatePanel({ icon, title, detail, tone = "default" }: { icon: React.ReactNode; title: string; detail: string; tone?: "default" | "danger" }) {
  return (
    <div className={`rounded-lg border p-8 text-center ${tone === "danger" ? "border-red-200 bg-red-50 text-red-700" : "border-black/10 bg-white text-ink"}`}>
      <div className="mx-auto flex justify-center">{icon}</div><div className="mt-3 font-bold">{title}</div><div className="mt-1 text-sm opacity-70">{detail}</div>
    </div>
  );
}

function LoadingCards() {
  return <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3" aria-label="Загрузка клубов">{Array.from({ length: 6 }, (_, index) => <div key={index} className="h-[29rem] animate-pulse rounded-lg border border-black/5 bg-white/70" />)}</div>;
}

function withCurrent(values: string[], current: string) {
  return current !== "all" && !values.includes(current) ? [current, ...values] : values;
}

function pluralizeProposals(count: number) {
  const mod100 = count % 100;
  const mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return `${count} предложений`;
  if (mod10 === 1) return `${count} предложение`;
  if (mod10 >= 2 && mod10 <= 4) return `${count} предложения`;
  return `${count} предложений`;
}

function formatDate(value: string | null) {
  if (!value) return "Нет данных";
  return new Intl.DateTimeFormat("ru-RU", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(value));
}

function inputClass(extra = "") {
  return `h-12 w-full rounded-lg border border-black/10 bg-[#fbfaf6] px-3 text-sm font-medium text-ink outline-none transition focus:border-court ${extra}`;
}

const pagerClass = "inline-flex h-11 items-center gap-2 rounded-lg border border-black/10 bg-white px-4 text-sm font-semibold text-ink disabled:opacity-40";
