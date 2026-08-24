"use client";
/* eslint-disable @next/next/no-img-element */

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, ArrowLeft, Clock3, ExternalLink, ShieldCheck, UserRound } from "lucide-react";

import { formatDate, reasonLabel, StatusBadge } from "@/components/admin/admin-report-list";
import type { AdminContentReport } from "@/components/admin/report-types";

export function AdminReportEditor({ reportId }: { reportId: string }) {
  const [report, setReport] = useState<AdminContentReport | null>(null);
  const [note, setNote] = useState("");
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(`/api/admin/reports/${encodeURIComponent(reportId)}`);
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Не удалось загрузить жалобу");
      setReport(payload.report);
      setNote(payload.report.resolutionNote || "");
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Не удалось загрузить жалобу");
    } finally {
      setLoading(false);
    }
  }, [reportId]);

  useEffect(() => { void load(); }, [load]);

  async function resolve(status: "actioned" | "dismissed") {
    if (!report || submitting) return;
    if (status === "actioned" && !window.confirm("Удалить пользовательский контент и деактивировать аккаунт? Это действие нельзя отменить из карточки жалобы.")) return;
    const resolutionNote = note.trim();
    if (resolutionNote.length < 3) {
      setError("Добавьте комментарий к решению — минимум 3 символа.");
      return;
    }
    setSubmitting(true);
    try {
      const response = await fetch(`/api/admin/reports/${encodeURIComponent(report.id)}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status, resolutionNote, expectedUpdatedAt: report.updatedAt })
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Не удалось сохранить решение");
      setReport(payload.report);
      setSuccess(status === "actioned" ? "Контент удалён, аккаунт деактивирован." : "Жалоба отклонена.");
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Не удалось сохранить решение");
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) return <div className="rounded-lg bg-white p-8 text-center text-sm text-ink/55">Загружаю жалобу…</div>;
  if (!report) return <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-red-700">{error || "Жалоба не найдена"}</div>;

  const overdue = report.status === "pending" && Date.parse(report.dueAt) < Date.now();
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <Link href="/admin/reports" className="inline-flex h-11 items-center gap-2 rounded-lg bg-black/5 px-4 text-sm font-semibold"><ArrowLeft className="h-4 w-4" />К жалобам</Link>
        <StatusBadge status={report.status} />
      </div>
      {error ? <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div> : null}
      {success ? <div className="rounded-lg border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">{success}</div> : null}

      <section className="rounded-lg border border-black/10 bg-white p-5">
        <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
          <div><div className="flex flex-wrap gap-2"><span className="rounded-full bg-black/5 px-2 py-1 text-xs font-bold">{reasonLabel(report.reason)}</span><span className="rounded-full bg-black/5 px-2 py-1 text-xs">{report.contentType}</span><span className="rounded-full bg-black/5 px-2 py-1 text-xs">{report.origin}</span></div><h1 className="mt-3 text-2xl font-bold">Жалоба {report.id}</h1><p className="mt-2 text-sm text-ink/65">Создана {formatDate(report.createdAt)}</p></div>
          <div className={`flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-bold ${overdue ? "bg-red-50 text-red-700" : "bg-amber-50 text-amber-800"}`}>{overdue ? <AlertTriangle className="h-4 w-4" /> : <Clock3 className="h-4 w-4" />}{overdue ? "Просрочено" : `Срок: ${formatDate(report.dueAt)}`}</div>
        </div>
      </section>

      <div className="grid gap-4 lg:grid-cols-2">
        <UserPanel title="Отправитель" user={report.reporterUser} fallbackName={report.reporterName} fallbackEmail={report.reporterEmail} />
        <section className="rounded-lg border border-red-200 bg-white p-5"><div className="flex items-center gap-2 text-sm font-bold text-red-700"><UserRound className="h-4 w-4" />На кого пожаловались</div><div className="mt-3 text-lg font-bold">{report.reportedUser?.name || report.reportedName || "Имя не указано"}</div><div className="text-sm text-ink/60">{report.reportedUser?.email || report.reportedEmail}</div>{report.reportedUserId ? <Link href={`/admin/players/${report.reportedUserId}`} className="mt-4 inline-flex items-center gap-2 text-sm font-bold text-court">Открыть игрока<ExternalLink className="h-4 w-4" /></Link> : <p className="mt-4 text-sm text-ink/50">Аккаунт удалён, снимок жалобы сохранён.</p>}</section>
      </div>

      <section className="rounded-lg border border-black/10 bg-white p-5"><h2 className="text-lg font-bold">Описание</h2><p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-ink/75">{report.details || "Пользователь не добавил подробности."}</p></section>
      <section className="rounded-lg border border-black/10 bg-white p-5">
        <h2 className="text-lg font-bold">Снимок контекста</h2>
        <p className="mt-1 text-xs text-ink/50">Сохранён в момент отправки жалобы и не меняется вместе с профилем.</p>
        <ContextMediaPreviews snapshot={report.contextSnapshot} />
        <pre className="mt-4 max-h-[440px] overflow-auto rounded-lg bg-[#f7f5ef] p-4 text-xs leading-5 text-ink/75">{formatSnapshot(report.contextSnapshot)}</pre>
      </section>

      <section className="rounded-lg border border-black/10 bg-white p-5">
        <div className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-court" /><h2 className="text-lg font-bold">Решение модератора</h2></div>
        {report.status === "pending" ? <div className="mt-4 space-y-4"><textarea value={note} onChange={(event) => setNote(event.target.value)} maxLength={1000} rows={5} placeholder="Что проверено и почему принято это решение" className="w-full rounded-lg border border-black/10 bg-[#faf9f5] p-3 text-sm outline-none focus:border-court" /><div className="flex flex-col gap-3 sm:flex-row"><button disabled={submitting} onClick={() => void resolve("actioned")} className="h-12 rounded-lg bg-red-700 px-5 text-sm font-bold text-white disabled:opacity-50">Удалить контент и деактивировать</button><button disabled={submitting} onClick={() => void resolve("dismissed")} className="h-12 rounded-lg bg-black/5 px-5 text-sm font-bold disabled:opacity-50">Отклонить жалобу</button></div></div> : <div className="mt-4 rounded-lg bg-[#f7f5ef] p-4 text-sm"><p className="font-semibold">{report.resolutionNote || "Комментарий не указан"}</p><p className="mt-2 text-ink/55">{report.reviewedByEmail || report.reviewedByUser?.email || "Модератор"} · {formatDate(report.reviewedAt)}</p></div>}
      </section>
    </div>
  );
}

function UserPanel({ title, user, fallbackName, fallbackEmail }: { title: string; user?: AdminContentReport["reporterUser"]; fallbackName?: string | null; fallbackEmail: string }) {
  return <section className="rounded-lg border border-black/10 bg-white p-5"><div className="text-sm font-bold text-ink/55">{title}</div><div className="mt-3 text-lg font-bold">{user?.name || fallbackName || "Имя не указано"}</div><div className="text-sm text-ink/60">{user?.email || fallbackEmail}</div></section>;
}

type SnapshotAttachment = {
  url: string;
  mimeType?: string;
  originalName?: string;
};

function ContextMediaPreviews({ snapshot }: { snapshot: unknown }) {
  const attachments = snapshotAttachments(snapshot);
  if (attachments.length === 0) return null;

  return (
    <div className="mt-4">
      <h3 className="text-sm font-bold">Медиа из жалобы</h3>
      <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {attachments.map((attachment, index) => {
          const isVideo = attachment.mimeType?.toLowerCase().startsWith("video/") ?? false;
          return (
            <div key={`${attachment.url}-${index}`} className="overflow-hidden rounded-lg border border-black/10 bg-black">
              {isVideo ? (
                <video controls preload="metadata" className="aspect-square w-full object-contain" aria-label={attachment.originalName || `Видео ${index + 1}`}>
                  <source src={attachment.url} type={attachment.mimeType} />
                </video>
              ) : (
                <a href={attachment.url} target="_blank" rel="noreferrer" className="block" aria-label={`Открыть ${attachment.originalName || `изображение ${index + 1}`}`}>
                  <img src={attachment.url} alt={attachment.originalName || `Вложение жалобы ${index + 1}`} className="aspect-square w-full object-contain" loading="lazy" />
                </a>
              )}
              <a href={attachment.url} target="_blank" rel="noreferrer" className="flex items-center justify-between gap-2 bg-white px-3 py-2 text-xs font-semibold text-court">
                <span className="truncate">{attachment.originalName || (isVideo ? `Видео ${index + 1}` : `Изображение ${index + 1}`)}</span>
                <ExternalLink className="h-3.5 w-3.5 shrink-0" />
              </a>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function snapshotAttachments(value: unknown): SnapshotAttachment[] {
  const snapshot = parseSnapshot(value);
  if (!snapshot || !Array.isArray(snapshot.attachments)) return [];

  return snapshot.attachments.flatMap((item): SnapshotAttachment[] => {
    if (!item || typeof item !== "object") return [];
    const attachment = item as Record<string, unknown>;
    const url = safeMediaURL(attachment.url);
    if (!url) return [];
    return [{
      url,
      mimeType: typeof attachment.mimeType === "string" ? attachment.mimeType : undefined,
      originalName: typeof attachment.originalName === "string" ? attachment.originalName : undefined
    }];
  });
}

function parseSnapshot(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
  if (typeof value !== "string") return null;
  try {
    const parsed: unknown = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function safeMediaURL(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const candidate = value.trim();
  if (candidate.startsWith("/") && !candidate.startsWith("//")) return candidate;
  try {
    const url = new URL(candidate);
    return url.protocol === "http:" || url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function formatSnapshot(value: unknown) {
  if (value == null) return "Контекст не сохранён";
  if (typeof value === "string") { try { return JSON.stringify(JSON.parse(value), null, 2); } catch { return value; } }
  try { return JSON.stringify(value, null, 2); } catch { return String(value); }
}
