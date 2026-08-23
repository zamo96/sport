"use client";

import Link from "next/link";
import { FormEvent, type ReactNode, useEffect, useMemo, useState } from "react";
import {
  AlertCircle,
  Building2,
  CheckCircle2,
  ChevronLeft,
  Database,
  History,
  MapPin,
  Save,
  ShieldCheck,
  X
} from "lucide-react";
import type { CourtSetting, Sport, Surface } from "@prisma/client";

import type { AdminClub, AdminClubAuditLog, AdminClubStatus } from "@/components/admin/club-types";
import {
  AVAILABLE_CITIES,
  DISTRICT_LABELS,
  DISTRICT_OPTIONS,
  SPORT_LABELS,
  SPORT_OPTIONS,
  SURFACE_LABELS
} from "@/lib/constants";

type DetailResponse = { club: AdminClub; auditLogs: AdminClubAuditLog[] };

type EditableProfile = Pick<
  AdminClub,
  | "name"
  | "address"
  | "city"
  | "district"
  | "locationLat"
  | "locationLng"
  | "surface"
  | "setting"
  | "supportedSports"
  | "phone"
  | "workingHours"
  | "yandexMapsUrl"
  | "websiteUrl"
  | "bookingUrl"
  | "about"
  | "amenities"
  | "messengerType"
  | "messengerUrl"
  | "photoUrl"
  | "photoUrls"
  | "priceRange"
  | "metroIds"
>;

const statuses: Array<{ value: AdminClubStatus; label: string }> = [
  { value: "active", label: "Активен" },
  { value: "needs_review", label: "Нужна проверка" },
  { value: "hidden", label: "Скрыт" },
  { value: "archived", label: "В архиве" }
];

export function AdminClubEditor({ clubId }: { clubId: string }) {
  const [club, setClub] = useState<AdminClub | null>(null);
  const [form, setForm] = useState<EditableProfile | null>(null);
  const [auditLogs, setAuditLogs] = useState<AdminClubAuditLog[]>([]);
  const [moderationNote, setModerationNote] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [conflict, setConflict] = useState(false);
  const [statusDialogOpen, setStatusDialogOpen] = useState(false);
  const [nextStatus, setNextStatus] = useState<AdminClubStatus>("needs_review");
  const [statusReason, setStatusReason] = useState("");
  const [statusSaving, setStatusSaving] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);

  async function loadClub() {
    setLoading(true);
    setError(null);
    setConflict(false);
    try {
      const response = await fetch(`/api/admin/clubs/${encodeURIComponent(clubId)}`);
      const payload = (await response.json()) as DetailResponse & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Не удалось загрузить клуб");
      applyResponse(payload);
      setModerationNote("");
    } catch (requestError) {
      setError(messageFrom(requestError, "Не удалось загрузить клуб"));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadClub();
    // clubId completely identifies this screen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clubId]);

  const changedProfile = useMemo(() => club && form ? buildChangedProfile(club, form) : {}, [club, form]);
  const dirty = Object.keys(changedProfile).length > 0;

  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  function applyResponse(payload: DetailResponse) {
    setClub(payload.club);
    setForm(toEditableProfile(payload.club));
    setAuditLogs(payload.auditLogs);
  }

  function setField<Key extends keyof EditableProfile>(key: Key, value: EditableProfile[Key]) {
    setForm((current) => current ? { ...current, [key]: value } : current);
    setNotice(null);
    setError(null);
    setConflict(false);
  }

  async function saveProfile(event: FormEvent) {
    event.preventDefault();
    if (!club || !form || !dirty) return;

    setSaving(true);
    setError(null);
    setNotice(null);
    setConflict(false);
    try {
      const response = await fetch(`/api/admin/clubs/${encodeURIComponent(club.id)}/profile`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          expectedUpdatedAt: club.updatedAt,
          profile: changedProfile,
          ...(moderationNote.trim() ? { moderationNote: moderationNote.trim() } : {})
        })
      });
      const payload = (await response.json()) as DetailResponse & { error?: string };
      if (!response.ok) {
        if (response.status === 409) setConflict(true);
        throw new Error(payload.error ?? mutationError(response.status));
      }
      applyResponse(payload);
      setModerationNote("");
      setNotice("Изменения сохранены и уже видны в публичной карточке клуба.");
    } catch (requestError) {
      setError(messageFrom(requestError, "Не удалось сохранить клуб"));
    } finally {
      setSaving(false);
    }
  }

  function openStatusDialog() {
    if (!club || dirty) return;
    const available = availableStatuses(club.status);
    setNextStatus(available[0]);
    setStatusReason("");
    setStatusError(null);
    setStatusDialogOpen(true);
  }

  async function changeStatus() {
    if (!club || statusReason.trim().length < 3 || nextStatus === club.status) return;

    setStatusSaving(true);
    setStatusError(null);
    setConflict(false);
    try {
      const response = await fetch(`/api/admin/clubs/${encodeURIComponent(club.id)}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ expectedUpdatedAt: club.updatedAt, status: nextStatus, reason: statusReason.trim() })
      });
      const payload = (await response.json()) as DetailResponse & { error?: string };
      if (!response.ok) {
        if (response.status === 409) setConflict(true);
        throw new Error(payload.error ?? mutationError(response.status));
      }
      applyResponse(payload);
      setStatusDialogOpen(false);
      setStatusReason("");
      setNotice(`Статус клуба изменён: ${statusLabel(payload.club.status).toLowerCase()}.`);
    } catch (requestError) {
      setStatusError(messageFrom(requestError, "Не удалось изменить статус"));
    } finally {
      setStatusSaving(false);
    }
  }

  if (loading) return <EditorSkeleton />;
  if (!club || !form) {
    return (
      <MessagePanel tone="danger" title="Карточка недоступна" detail={error ?? "Клуб не найден"}>
        <button type="button" onClick={() => void loadClub()} className="mt-4 rounded-lg bg-ink px-4 py-3 text-sm font-semibold text-white">Повторить</button>
      </MessagePanel>
    );
  }

  return (
    <div className="space-y-5">
      <header className="overflow-hidden rounded-lg border border-black/10 bg-white shadow-[0_10px_30px_rgba(17,38,29,0.08)]">
        <div
          className="flex h-40 items-center justify-center bg-gradient-to-br from-mint to-cream bg-cover bg-center text-court md:h-52"
          style={form.photoUrl ? { backgroundImage: `linear-gradient(rgba(17,38,29,.2),rgba(17,38,29,.2)),url(${JSON.stringify(form.photoUrl)})` } : undefined}
          role={form.photoUrl ? "img" : undefined}
          aria-label={form.photoUrl ? `Фотография клуба ${form.name}` : undefined}
        >
          {!form.photoUrl ? <Building2 className="h-14 w-14" /> : null}
        </div>
        <div className="flex flex-col gap-4 p-5 lg:flex-row lg:items-start lg:justify-between">
          <div className="min-w-0">
            <Link
              href="/admin/clubs"
              onClick={(event) => {
                if (dirty && !window.confirm("Есть несохранённые изменения. Покинуть карточку клуба?")) event.preventDefault();
              }}
              className="inline-flex items-center gap-1 text-xs font-semibold text-court"
            >
              <ChevronLeft className="h-3.5 w-3.5" /> Все клубы
            </Link>
            <h1 className="mt-2 truncate text-2xl font-bold text-ink md:text-3xl">{form.name || "Клуб без названия"}</h1>
            <div className="mt-1 flex items-start gap-1 text-sm text-ink/60"><MapPin className="mt-0.5 h-4 w-4 shrink-0" /> {[form.city, districtLabel(form.district), form.address].filter(Boolean).join(" · ")}</div>
            <div className="mt-3 flex flex-wrap gap-2">
              <StatusBadge status={club.status} />
              <SmallBadge tone="muted">Источник: {club.sourceType}</SmallBadge>
              {club.pendingProposalCount > 0 ? <SmallBadge tone="warning">{club.pendingProposalCount} предложений на проверке</SmallBadge> : null}
              {dirty ? <SmallBadge tone="warning">Есть несохранённые изменения</SmallBadge> : null}
            </div>
          </div>
          <button
            type="button"
            onClick={openStatusDialog}
            disabled={dirty}
            title={dirty ? "Сначала сохраните или отмените изменения клуба" : undefined}
            className="inline-flex h-12 items-center justify-center gap-2 rounded-lg bg-ink px-5 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
          >
            <ShieldCheck className="h-4 w-4" /> Изменить статус
          </button>
        </div>
      </header>

      {notice ? <MessagePanel tone="success" title="Готово" detail={notice} /> : null}
      {error ? (
        <MessagePanel tone="danger" title={conflict ? "Карточка уже изменилась" : "Операция не выполнена"} detail={error}>
          {conflict ? <button type="button" onClick={() => void loadClub()} className="mt-3 rounded-lg bg-ink px-4 py-2.5 text-sm font-semibold text-white">Загрузить свежую версию</button> : null}
        </MessagePanel>
      ) : null}

      <form onSubmit={saveProfile} className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]">
        <div className="space-y-5">
          <EditorSection title="Основные данные" icon={<Building2 className="h-5 w-5" />}>
            <div className="grid gap-4 md:grid-cols-2">
              <Field label="Название"><input value={form.name} onChange={(event) => setField("name", event.target.value)} className={inputClass} maxLength={160} required /></Field>
              <Field label="Город">
                <input value={form.city} onChange={(event) => setField("city", event.target.value)} list="admin-club-cities" className={inputClass} maxLength={100} required />
                <datalist id="admin-club-cities">{Array.from(new Set([...AVAILABLE_CITIES, form.city])).map((value) => <option key={value} value={value} />)}</datalist>
              </Field>
              <Field label="Адрес"><input value={form.address} onChange={(event) => setField("address", event.target.value)} className={inputClass} maxLength={300} required /></Field>
              <Field label="Район">
                <select value={form.district ?? ""} onChange={(event) => setField("district", event.target.value || null)} className={inputClass}>
                  <option value="">Не указан</option>
                  {form.district && !DISTRICT_OPTIONS.includes(form.district as typeof DISTRICT_OPTIONS[number]) ? <option value={form.district}>{form.district}</option> : null}
                  {DISTRICT_OPTIONS.map((value) => <option key={value} value={value}>{DISTRICT_LABELS[value]}</option>)}
                </select>
              </Field>
              <Field label="Широта"><input type="number" step="any" min={-90} max={90} value={form.locationLat} onChange={(event) => setField("locationLat", Number(event.target.value))} className={inputClass} required /></Field>
              <Field label="Долгота"><input type="number" step="any" min={-180} max={180} value={form.locationLng} onChange={(event) => setField("locationLng", Number(event.target.value))} className={inputClass} required /></Field>
              <Field label="Покрытие">
                <select value={form.surface} onChange={(event) => setField("surface", event.target.value as Surface)} className={inputClass}>
                  {Object.entries(SURFACE_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </Field>
              <Field label="Расположение">
                <select value={form.setting} onChange={(event) => setField("setting", event.target.value as CourtSetting)} className={inputClass}>
                  <option value="indoor">В помещении</option><option value="outdoor">На улице</option>
                </select>
              </Field>
              <Field label="Диапазон цен"><input value={form.priceRange} onChange={(event) => setField("priceRange", event.target.value)} className={inputClass} maxLength={160} required /></Field>
              <Field label="Часы работы"><input value={form.workingHours ?? ""} onChange={(event) => setField("workingHours", nullable(event.target.value))} className={inputClass} maxLength={500} /></Field>
            </div>
            <Field label="Описание"><textarea value={form.about ?? ""} onChange={(event) => setField("about", nullable(event.target.value))} className={`${inputClass} min-h-32 py-3`} maxLength={3000} /></Field>
          </EditorSection>

          <EditorSection title="Виды спорта">
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {SPORT_OPTIONS.map((sport) => {
                const checked = form.supportedSports.includes(sport);
                return (
                  <label key={sport} className={`flex cursor-pointer items-center gap-2 rounded-lg border px-3 py-3 text-sm font-semibold ${checked ? "border-court/40 bg-mint" : "border-black/10 bg-[#fbfaf6]"}`}>
                    <input type="checkbox" checked={checked} disabled={checked && form.supportedSports.length === 1} onChange={() => setField("supportedSports", toggle(form.supportedSports, sport))} className="h-4 w-4 accent-court" />
                    {SPORT_LABELS[sport]}
                  </label>
                );
              })}
            </div>
          </EditorSection>

          <EditorSection title="Контакты и ссылки">
            <div className="grid gap-4 md:grid-cols-2">
              <Field label="Телефон"><input value={form.phone ?? ""} onChange={(event) => setField("phone", nullable(event.target.value))} className={inputClass} maxLength={100} /></Field>
              <Field label="Сайт"><input type="url" value={form.websiteUrl ?? ""} onChange={(event) => setField("websiteUrl", nullable(event.target.value))} className={inputClass} placeholder="https://…" /></Field>
              <Field label="Ссылка на бронирование"><input type="url" value={form.bookingUrl ?? ""} onChange={(event) => setField("bookingUrl", nullable(event.target.value))} className={inputClass} placeholder="https://…" /></Field>
              <Field label="Яндекс Карты"><input type="url" value={form.yandexMapsUrl ?? ""} onChange={(event) => setField("yandexMapsUrl", nullable(event.target.value))} className={inputClass} placeholder="https://…" /></Field>
              <Field label="Мессенджер"><input value={form.messengerType ?? ""} onChange={(event) => setField("messengerType", nullable(event.target.value))} className={inputClass} maxLength={80} placeholder="Telegram, WhatsApp…" /></Field>
              <Field label="Ссылка на мессенджер"><input type="url" value={form.messengerUrl ?? ""} onChange={(event) => setField("messengerUrl", nullable(event.target.value))} className={inputClass} placeholder="https://…" /></Field>
            </div>
          </EditorSection>

          <EditorSection title="Удобства и метро">
            <div className="grid gap-4 md:grid-cols-2">
              <Field label="Удобства — по одному на строку"><textarea value={form.amenities.join("\n")} onChange={(event) => setField("amenities", lines(event.target.value, 12))} className={`${inputClass} min-h-32 py-3`} /></Field>
              <Field label="Станции метро — системный ID на строку"><textarea value={form.metroIds.join("\n")} onChange={(event) => setField("metroIds", lines(event.target.value, 8))} className={`${inputClass} min-h-32 py-3 font-mono text-xs`} /></Field>
            </div>
            {club.metroNames.length > 0 ? <p className="mt-3 text-xs text-ink/55">Сейчас связаны: {club.metroNames.join(", ")}.</p> : null}
          </EditorSection>

          <EditorSection title="Фотографии">
            <div className="grid gap-4 md:grid-cols-2">
              <Field label="Главная фотография"><input type="url" value={form.photoUrl ?? ""} onChange={(event) => setField("photoUrl", nullable(event.target.value))} className={inputClass} placeholder="https://…" /></Field>
              <Field label="Галерея — один URL на строку"><textarea value={form.photoUrls.join("\n")} onChange={(event) => setField("photoUrls", lines(event.target.value, 8))} className={`${inputClass} min-h-28 py-3`} placeholder="https://…" /></Field>
            </div>
            <p className="mt-3 text-xs text-ink/50">Здесь меняются только существующие ссылки. Загрузка файлов в окне модератора не выполняется.</p>
          </EditorSection>

          <div className="sticky bottom-4 z-10 flex flex-col gap-3 rounded-lg border border-black/10 bg-white/95 p-3 shadow-[0_10px_30px_rgba(17,38,29,0.18)] backdrop-blur sm:flex-row sm:items-end sm:justify-between">
            <Field label="Комментарий модератора (необязательно)" className="min-w-0 flex-1"><input value={moderationNote} onChange={(event) => setModerationNote(event.target.value)} className={inputClass} maxLength={500} /></Field>
            <div className="flex gap-2">
              <button type="button" disabled={!dirty || saving} onClick={() => { setForm(toEditableProfile(club)); setModerationNote(""); setError(null); setConflict(false); }} className="h-12 rounded-lg border border-black/10 px-4 text-sm font-semibold text-ink disabled:opacity-40">Отменить</button>
              <button type="submit" disabled={!dirty || saving} className="inline-flex h-12 items-center gap-2 rounded-lg bg-court px-5 text-sm font-bold text-white disabled:opacity-40"><Save className="h-4 w-4" /> {saving ? "Сохраняем…" : "Сохранить"}</button>
            </div>
          </div>
        </div>

        <aside className="space-y-5">
          <EditorSection title="Использование" icon={<Database className="h-5 w-5" />}>
            <dl className="grid grid-cols-2 gap-2 text-xs">
              <Meta label="Игроки" value={club.usageCounts.members} />
              <Meta label="Запросы игр" value={club.usageCounts.gameRequests} />
              <Meta label="Поиски" value={club.usageCounts.gameSearches} />
              <Meta label="Регулярные игры" value={club.usageCounts.regularPairs} />
              <Meta label="Личные активности" value={club.usageCounts.personalActivities} />
            </dl>
          </EditorSection>

          <EditorSection title="Происхождение записи" icon={<Database className="h-5 w-5" />}>
            <ReadOnly label="Источник" value={club.sourceType} />
            <ReadOnly label="ID у источника" value={club.sourceExternalId} mono />
            <ReadOnly label="Ссылка на источник" value={club.sourceUrl} />
            <ReadOnly label="Создан" value={formatDateTime(club.createdAt)} />
            <ReadOnly label="Обновлён" value={formatDateTime(club.updatedAt)} />
            <ReadOnly label="Проверен" value={formatDateTime(club.lastCheckedAt)} />
            <ReadOnly label="Последний раз найден" value={formatDateTime(club.lastSeenAt)} />
            <ReadOnly label="Проверка сайта" value={formatDateTime(club.websiteLastCheckedAt)} />
            <ReadOnly label="Модерировал" value={club.moderatedByEmail} />
            <ReadOnly label="Дата модерации" value={formatDateTime(club.moderatedAt)} />
            <ReadOnly label="Статус закреплён модератором" value={club.manualStatusOverride ? "Да" : "Нет"} />
            <div className="mt-3">
              <div className="text-xs font-semibold text-ink/45">Защищено от автообновления</div>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {club.manualOverrideFields.length ? club.manualOverrideFields.map((field) => <SmallBadge key={field} tone="muted">{fieldLabel(field)}</SmallBadge>) : <span className="text-xs text-ink/55">Нет ручных изменений</span>}
              </div>
            </div>
          </EditorSection>

          <EditorSection title="История модерации" icon={<History className="h-5 w-5" />}>
            {auditLogs.length === 0 ? <p className="text-sm text-ink/55">Действий модератора пока нет.</p> : <div className="divide-y divide-black/10">{auditLogs.map((log) => <AuditRow key={log.id} log={log} />)}</div>}
          </EditorSection>
        </aside>
      </form>

      {statusDialogOpen ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/45 p-4 sm:items-center" role="dialog" aria-modal="true" aria-labelledby="club-status-title">
          <div className="w-full max-w-lg rounded-lg bg-white p-5 shadow-2xl">
            <div className="flex items-start justify-between gap-4">
              <div><h2 id="club-status-title" className="text-xl font-bold text-ink">Изменить статус клуба</h2><p className="mt-1 text-sm text-ink/60">Текущий статус: {statusLabel(club.status).toLowerCase()}.</p></div>
              <button type="button" onClick={() => setStatusDialogOpen(false)} disabled={statusSaving} className="rounded-md p-2 text-ink/55 hover:bg-black/5"><X className="h-5 w-5" /></button>
            </div>
            <div className="mt-4 space-y-4">
              <Field label="Новый статус">
                <select value={nextStatus} onChange={(event) => setNextStatus(event.target.value as AdminClubStatus)} className={inputClass}>
                  {availableStatuses(club.status).map((value) => <option key={value} value={value}>{statusLabel(value)}</option>)}
                </select>
              </Field>
              <Field label="Причина изменения"><textarea value={statusReason} onChange={(event) => setStatusReason(event.target.value)} className={`${inputClass} min-h-28 py-3`} minLength={3} maxLength={500} autoFocus /></Field>
              {statusError ? (
                <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
                  <div className="flex gap-2"><AlertCircle className="h-5 w-5 shrink-0" /> <span>{statusError}</span></div>
                  {conflict ? <button type="button" onClick={() => { setStatusDialogOpen(false); void loadClub(); }} className="mt-3 rounded-lg bg-ink px-4 py-2.5 text-sm font-semibold text-white">Загрузить свежую версию</button> : null}
                </div>
              ) : null}
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <button type="button" onClick={() => setStatusDialogOpen(false)} disabled={statusSaving} className="h-11 rounded-lg border border-black/10 px-4 text-sm font-semibold text-ink">Отмена</button>
              <button type="button" onClick={() => void changeStatus()} disabled={statusSaving || statusReason.trim().length < 3} className="h-11 rounded-lg bg-ink px-5 text-sm font-bold text-white disabled:opacity-40">{statusSaving ? "Сохраняем…" : "Изменить статус"}</button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function toEditableProfile(club: AdminClub): EditableProfile {
  return {
    name: club.name,
    address: club.address,
    city: club.city,
    district: club.district,
    locationLat: club.locationLat,
    locationLng: club.locationLng,
    surface: club.surface,
    setting: club.setting,
    supportedSports: [...club.supportedSports],
    phone: club.phone,
    workingHours: club.workingHours,
    yandexMapsUrl: club.yandexMapsUrl,
    websiteUrl: club.websiteUrl,
    bookingUrl: club.bookingUrl,
    about: club.about,
    amenities: [...club.amenities],
    messengerType: club.messengerType,
    messengerUrl: club.messengerUrl,
    photoUrl: club.photoUrl,
    photoUrls: [...club.photoUrls],
    priceRange: club.priceRange,
    metroIds: [...club.metroIds]
  };
}

function buildChangedProfile(club: AdminClub, form: EditableProfile): Partial<EditableProfile> {
  const original = toEditableProfile(club);
  const changed = Object.fromEntries(
    (Object.keys(form) as Array<keyof EditableProfile>)
      .filter((key) => JSON.stringify(form[key] ?? null) !== JSON.stringify(original[key] ?? null))
      .map((key) => [key, form[key]])
  ) as Partial<EditableProfile>;

  if (changed.locationLat !== undefined || changed.locationLng !== undefined) {
    changed.locationLat = form.locationLat;
    changed.locationLng = form.locationLng;
  }
  if (changed.city !== undefined) {
    changed.district = form.district;
    changed.metroIds = form.metroIds;
  }
  return changed;
}

function availableStatuses(current: AdminClubStatus): AdminClubStatus[] {
  if (current === "archived") return ["needs_review"];
  return statuses.map(({ value }) => value).filter((value) => value !== current);
}

function statusLabel(status: AdminClubStatus) {
  return statuses.find(({ value }) => value === status)?.label ?? status;
}

function StatusBadge({ status }: { status: AdminClubStatus }) {
  const styles: Record<AdminClubStatus, string> = { active: "bg-emerald-100 text-emerald-700", needs_review: "bg-amber-100 text-amber-800", hidden: "bg-slate-200 text-slate-700", archived: "bg-red-100 text-red-700" };
  return <span className={`rounded-full px-2.5 py-1 text-[11px] font-bold ${styles[status]}`}>{statusLabel(status)}</span>;
}

function SmallBadge({ tone, children }: { tone: "muted" | "warning"; children: ReactNode }) {
  return <span className={`rounded-full px-2.5 py-1 text-[11px] font-bold ${tone === "warning" ? "bg-amber-100 text-amber-800" : "bg-black/5 text-ink/60"}`}>{children}</span>;
}

function EditorSection({ title, icon, children }: { title: string; icon?: ReactNode; children: ReactNode }) {
  return <section className="rounded-lg border border-black/10 bg-white p-4 shadow-[0_10px_30px_rgba(17,38,29,0.06)]"><div className="mb-4 flex items-center gap-2 text-base font-bold text-ink">{icon ? <span className="text-court">{icon}</span> : null}{title}</div>{children}</section>;
}

function Field({ label, children, className = "" }: { label: string; children: ReactNode; className?: string }) {
  return <label className={`block ${className}`}><span className="mb-1.5 block text-xs font-semibold text-ink/55">{label}</span>{children}</label>;
}

function Meta({ label, value }: { label: string; value: number }) {
  return <div className="rounded-md bg-[#fbfaf6] p-2.5"><dt className="text-ink/45">{label}</dt><dd className="mt-1 text-lg font-bold text-ink">{value.toLocaleString("ru-RU")}</dd></div>;
}

function ReadOnly({ label, value, mono = false }: { label: string; value: string | null; mono?: boolean }) {
  return <div className="border-b border-black/10 py-2.5 last:border-0"><div className="text-xs font-semibold text-ink/45">{label}</div><div className={`mt-1 break-words text-sm text-ink/75 ${mono ? "font-mono text-xs" : ""}`}>{value || "Нет данных"}</div></div>;
}

function AuditRow({ log }: { log: AdminClubAuditLog }) {
  const fields = auditFields(log);
  return <div className="py-3"><div className="flex items-start justify-between gap-2"><div className="text-sm font-bold text-ink">{log.action === "STATUS_CHANGED" ? "Изменён статус" : "Обновлён профиль"}</div><div className="shrink-0 text-[11px] text-ink/45">{formatDateTime(log.createdAt)}</div></div><div className="mt-1 text-xs text-ink/55">{log.actorEmail}</div>{fields ? <div className="mt-1 text-xs leading-5 text-ink/65">{fields}</div> : null}{log.reason ? <div className="mt-2 rounded-md bg-[#fbfaf6] px-2.5 py-2 text-xs leading-5 text-ink/70">{log.reason}</div> : null}</div>;
}

function auditFields(log: AdminClubAuditLog) {
  const after = isRecord(log.after) ? log.after : null;
  if (!after) return "";
  if (typeof after.status === "string") return `Новый статус: ${statusLabel(after.status as AdminClubStatus).toLowerCase()}`;
  const keys = Object.keys(after).map(fieldLabel);
  return keys.length ? `Поля: ${keys.join(", ")}` : "";
}

function MessagePanel({ tone, title, detail, children }: { tone: "success" | "danger"; title: string; detail: string; children?: ReactNode }) {
  const success = tone === "success";
  return <div className={`rounded-lg border p-4 ${success ? "border-emerald-200 bg-emerald-50 text-emerald-800" : "border-red-200 bg-red-50 text-red-700"}`}><div className="flex gap-3">{success ? <CheckCircle2 className="h-5 w-5 shrink-0" /> : <AlertCircle className="h-5 w-5 shrink-0" />}<div><div className="font-bold">{title}</div><div className="mt-1 text-sm leading-6 opacity-80">{detail}</div>{children}</div></div></div>;
}

function EditorSkeleton() {
  return <div className="space-y-5" aria-label="Загрузка клуба"><div className="h-80 animate-pulse rounded-lg bg-white/70" /><div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]"><div className="h-[40rem] animate-pulse rounded-lg bg-white/70" /><div className="h-96 animate-pulse rounded-lg bg-white/70" /></div></div>;
}

function toggle(values: Sport[], value: Sport) {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

function lines(value: string, max: number) {
  return Array.from(new Set(value.split("\n").map((item) => item.trim()).filter(Boolean))).slice(0, max);
}

function nullable(value: string) {
  return value.trim() ? value : null;
}

function districtLabel(value: string | null) {
  return value && value in DISTRICT_LABELS ? DISTRICT_LABELS[value as keyof typeof DISTRICT_LABELS] : value;
}

function fieldLabel(field: string) {
  const labels: Record<string, string> = {
    name: "название", address: "адрес", city: "город", district: "район", locationLat: "широта", locationLng: "долгота",
    surface: "покрытие", setting: "расположение", supportedSports: "виды спорта", phone: "телефон", workingHours: "часы работы",
    yandexMapsUrl: "Яндекс Карты", websiteUrl: "сайт", bookingUrl: "бронирование", about: "описание", amenities: "удобства",
    messengerType: "мессенджер", messengerUrl: "ссылка мессенджера", photoUrl: "главное фото", photoUrls: "галерея", priceRange: "цены", metroIds: "метро"
  };
  return labels[field] ?? field;
}

function formatDateTime(value: string | null) {
  if (!value) return "Нет данных";
  return new Intl.DateTimeFormat("ru-RU", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function mutationError(status: number) {
  return status === 409 ? "Клуб уже изменён другим модератором. Загрузите свежую версию и повторите правку." : "Не удалось сохранить изменения";
}

function messageFrom(error: unknown, fallback: string) {
  return error instanceof Error ? error.message : fallback;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

const inputClass = "h-12 w-full rounded-lg border border-black/10 bg-[#fbfaf6] px-3 text-sm font-medium text-ink outline-none transition focus:border-court";
