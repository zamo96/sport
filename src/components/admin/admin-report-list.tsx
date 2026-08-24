"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AlertTriangle, ChevronLeft, ChevronRight, Clock3, Search } from "lucide-react";

import type { AdminContentReport, AdminReportPagination } from "@/components/admin/report-types";

type Payload = { reports: AdminContentReport[]; pagination: AdminReportPagination };

export function AdminReportList() {
  const [status, setStatus] = useState("pending");
  const [origin, setOrigin] = useState("all");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<Payload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const controller = new AbortController();
    const params = new URLSearchParams({ status, origin, page: String(page), limit: "24" });
    if (query.trim()) params.set("q", query.trim());
    setLoading(true);
    fetch(`/api/admin/reports?${params}`, { signal: controller.signal })
      .then(async (response) => {
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "Не удалось загрузить жалобы");
        setData(payload);
        setError(null);
      })
      .catch((cause: unknown) => {
        if (cause instanceof DOMException && cause.name === "AbortError") return;
        setError(cause instanceof Error ? cause.message : "Не удалось загрузить жалобы");
      })
      .finally(() => setLoading(false));
    return () => controller.abort();
  }, [status, origin, query, page]);

  return (
    <div className="space-y-4">
      <div className="grid gap-3 rounded-lg border border-black/10 bg-white p-4 md:grid-cols-[minmax(0,1fr)_180px_180px]">
        <label className="relative block">
          <Search className="absolute left-3 top-3.5 h-4 w-4 text-ink/45" />
          <input value={query} onChange={(event) => { setQuery(event.target.value); setPage(1); }} placeholder="ID, имя или email" className="h-11 w-full rounded-lg border border-black/10 bg-[#faf9f5] pl-10 pr-3 text-sm outline-none focus:border-court" />
        </label>
        <select value={status} onChange={(event) => { setStatus(event.target.value); setPage(1); }} className="h-11 rounded-lg border border-black/10 bg-[#faf9f5] px-3 text-sm">
          <option value="pending">Ожидают решения</option>
          <option value="actioned">Приняты меры</option>
          <option value="dismissed">Отклонены</option>
          <option value="all">Все статусы</option>
        </select>
        <select value={origin} onChange={(event) => { setOrigin(event.target.value); setPage(1); }} className="h-11 rounded-lg border border-black/10 bg-[#faf9f5] px-3 text-sm">
          <option value="all">Все источники</option>
          <option value="report">Жалобы</option>
          <option value="block">Блокировки</option>
        </select>
      </div>

      {error ? <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div> : null}
      {loading ? <div className="rounded-lg bg-white p-8 text-center text-sm text-ink/55">Загружаю жалобы…</div> : null}
      {!loading && data?.reports.length === 0 ? <div className="rounded-lg bg-white p-8 text-center text-sm text-ink/55">Жалоб с такими фильтрами нет.</div> : null}

      <div className="grid gap-3">
        {data?.reports.map((report) => <ReportCard key={report.id} report={report} />)}
      </div>

      {data && data.pagination.totalPages > 1 ? (
        <div className="flex items-center justify-between rounded-lg bg-white p-3 text-sm">
          <button disabled={page <= 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="inline-flex h-10 items-center gap-1 rounded-lg bg-black/5 px-3 disabled:opacity-40"><ChevronLeft className="h-4 w-4" />Назад</button>
          <span>{data.pagination.page} из {data.pagination.totalPages} · {data.pagination.total} всего</span>
          <button disabled={page >= data.pagination.totalPages} onClick={() => setPage((value) => value + 1)} className="inline-flex h-10 items-center gap-1 rounded-lg bg-black/5 px-3 disabled:opacity-40">Далее<ChevronRight className="h-4 w-4" /></button>
        </div>
      ) : null}
    </div>
  );
}

function ReportCard({ report }: { report: AdminContentReport }) {
  const overdue = report.status === "pending" && Date.parse(report.dueAt) < Date.now();
  const targetName = report.reportedUser?.name || report.reportedName || report.reportedUser?.email || report.reportedEmail;
  return (
    <Link href={`/admin/reports/${report.id}`} className={`rounded-lg border bg-white p-4 transition hover:-translate-y-0.5 hover:shadow-md ${overdue ? "border-red-300" : "border-black/10"}`}>
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={report.status} />
            <span className="rounded-full bg-black/5 px-2 py-1 text-xs font-semibold">{reasonLabel(report.reason)}</span>
            <span className="rounded-full bg-black/5 px-2 py-1 text-xs">{report.origin === "block" ? "Блокировка" : "Жалоба"}</span>
          </div>
          <h2 className="mt-3 text-lg font-bold">На пользователя: {targetName}</h2>
          <p className="mt-1 text-sm text-ink/60">{report.details || "Подробности не указаны"}</p>
        </div>
        <div className={`flex items-center gap-2 text-sm font-semibold ${overdue ? "text-red-700" : "text-ink/55"}`}>
          {overdue ? <AlertTriangle className="h-4 w-4" /> : <Clock3 className="h-4 w-4" />}
          {overdue ? "Срок истёк" : `До ${formatDate(report.dueAt)}`}
        </div>
      </div>
    </Link>
  );
}

export function StatusBadge({ status }: { status: string }) {
  const label = status === "pending" ? "На проверке" : status === "actioned" ? "Меры приняты" : "Отклонена";
  const colors = status === "pending" ? "bg-amber-100 text-amber-800" : status === "actioned" ? "bg-red-100 text-red-800" : "bg-emerald-100 text-emerald-800";
  return <span className={`rounded-full px-2 py-1 text-xs font-bold ${colors}`}>{label}</span>;
}

export function reasonLabel(reason: string) {
  return ({ abusive_behavior: "Агрессивное поведение", harassment: "Травля", hate_speech: "Язык ненависти", sexual_content: "Неприемлемый контент", violence: "Угрозы", spam: "Спам", impersonation: "Выдаёт себя за другого", privacy: "Приватность", illegal_content: "Незаконный контент", other: "Другое" } as Record<string, string>)[reason] || reason;
}

export function formatDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ru-RU", { dateStyle: "short", timeStyle: "short" }).format(date);
}
