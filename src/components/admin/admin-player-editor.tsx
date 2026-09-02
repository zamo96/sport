"use client";

import Link from "next/link";
import { FormEvent, useEffect, useMemo, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  ChevronLeft,
  Clock3,
  History,
  Save,
  ShieldCheck,
  ShieldOff,
  UserRoundCog,
  X
} from "lucide-react";
import type { Gender, PlayFormat, Sport, Surface } from "@prisma/client";

import {
  AVAILABLE_CITIES,
  DAY_LABELS,
  DAY_OPTIONS,
  DISTRICT_LABELS,
  DISTRICT_OPTIONS,
  GENDER_LABELS,
  PLAY_FORMAT_LABELS,
  SPORT_LABELS,
  SPORT_OPTIONS,
  SURFACE_LABELS,
  TIME_RANGE_LABELS,
  TIME_RANGE_OPTIONS
} from "@/lib/constants";
import { Avatar } from "@/components/ui/avatar";
import type { AdminPlayer, AdminPlayerAuditLog } from "@/components/admin/player-types";

type DetailResponse = { player: AdminPlayer; auditLogs: AdminPlayerAuditLog[] };
type MutationResponse = { player: AdminPlayer; effects?: StatusEffects };
type StatusEffects = { sessionsRevoked: number; pushDevicesDisabled: number; searchesClosed: number };

type EditableProfile = Pick<
  AdminPlayer,
  | "name"
  | "age"
  | "gender"
  | "city"
  | "district"
  | "preferredDistricts"
  | "tennisLevel"
  | "preferredSports"
  | "sportLevels"
  | "preferredPlayFormat"
  | "preferredSurface"
  | "bio"
  | "avatarUrl"
  | "profilePhotoUrls"
  | "profileVideoUrls"
  | "availableDays"
  | "availableTimeRanges"
  | "availabilityByDay"
  | "isLookingForGame"
>;

export function AdminPlayerEditor({ playerId, currentAdminId }: { playerId: string; currentAdminId: string }) {
  const [player, setPlayer] = useState<AdminPlayer | null>(null);
  const [form, setForm] = useState<EditableProfile | null>(null);
  const [auditLogs, setAuditLogs] = useState<AdminPlayerAuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [statusDialogOpen, setStatusDialogOpen] = useState(false);
  const [statusReason, setStatusReason] = useState("");
  const [statusSaving, setStatusSaving] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);

  async function loadPlayer() {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch(`/api/admin/players/${encodeURIComponent(playerId)}`);
      const payload = (await response.json()) as DetailResponse & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Не удалось загрузить карточку игрока");
      setPlayer(payload.player);
      setForm(toEditableProfile(payload.player));
      setAuditLogs(payload.auditLogs);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось загрузить карточку игрока");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadPlayer();
    // playerId is the complete identity of this screen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playerId]);

  const dirty = useMemo(
    () => Boolean(player && form && JSON.stringify(form) !== JSON.stringify(toEditableProfile(player))),
    [form, player]
  );
  const selfDeactivationForbidden = player?.id === currentAdminId && player.accountStatus === "active";

  function setField<Key extends keyof EditableProfile>(key: Key, value: EditableProfile[Key]) {
    setForm((current) => (current ? { ...current, [key]: value } : current));
    setNotice(null);
  }

  async function saveProfile(event: FormEvent) {
    event.preventDefault();
    if (!player || !form) return;

    setSaving(true);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch(`/api/admin/players/${encodeURIComponent(player.id)}/profile`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ expectedUpdatedAt: player.updatedAt, profile: normalizeProfileForSave(form) })
      });
      const payload = (await response.json()) as MutationResponse & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? conflictMessage(response.status));
      setPlayer(payload.player);
      setForm(toEditableProfile(payload.player));
      setNotice("Профиль сохранён. Изменения уже видны в карточке игрока.");
      await refreshAuditLogs(payload.player);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось сохранить профиль");
    } finally {
      setSaving(false);
    }
  }

  async function refreshAuditLogs(nextPlayer: AdminPlayer) {
    try {
      const response = await fetch(`/api/admin/players/${encodeURIComponent(nextPlayer.id)}`);
      if (!response.ok) return;
      const payload = (await response.json()) as DetailResponse;
      setAuditLogs(payload.auditLogs);
    } catch {
      // Saving succeeded; a failed history refresh should not replace that outcome.
    }
  }

  async function changeStatus() {
    if (!player || statusReason.trim().length < 3) return;
    const nextStatus = player.accountStatus === "active" ? "deactivated" : "active";

    setStatusSaving(true);
    setStatusError(null);
    setNotice(null);
    try {
      const response = await fetch(`/api/admin/players/${encodeURIComponent(player.id)}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: nextStatus, reason: statusReason.trim(), expectedUpdatedAt: player.updatedAt })
      });
      const payload = (await response.json()) as MutationResponse & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? conflictMessage(response.status));
      setPlayer(payload.player);
      setForm(toEditableProfile(payload.player));
      setStatusDialogOpen(false);
      setStatusReason("");
      setNotice(buildStatusNotice(nextStatus, payload.effects));
      await refreshAuditLogs(payload.player);
    } catch (requestError) {
      setStatusError(requestError instanceof Error ? requestError.message : "Не удалось изменить статус аккаунта");
    } finally {
      setStatusSaving(false);
    }
  }

  if (loading) return <EditorSkeleton />;

  if (!player || !form) {
    return (
      <MessagePanel tone="danger" title="Карточка недоступна" detail={error ?? "Игрок не найден"}>
        <button type="button" onClick={() => void loadPlayer()} className="mt-4 rounded-lg bg-ink px-4 py-3 text-sm font-semibold text-white">
          Повторить
        </button>
      </MessagePanel>
    );
  }

  return (
    <div className="space-y-5">
      <header className="rounded-lg border border-black/10 bg-white p-5 shadow-[0_10px_30px_rgba(17,38,29,0.08)]">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div className="flex min-w-0 items-start gap-4">
            <Avatar src={form.avatarUrl} alt={form.name ?? player.email} size="lg" className="shrink-0" />
            <div className="min-w-0">
              <Link href="/admin/players" className="inline-flex items-center gap-1 text-xs font-semibold text-court">
                <ChevronLeft className="h-3.5 w-3.5" /> Все игроки
              </Link>
              <h1 className="mt-2 truncate text-2xl font-bold text-ink md:text-3xl">{form.name || "Игрок без имени"}</h1>
              <div className="mt-1 truncate text-sm text-ink/60">{player.email}</div>
              <div className="mt-3 flex flex-wrap gap-2">
                <AccountStatusBadge status={player.accountStatus} />
                <SmallBadge tone={player.isVerified ? "success" : "muted"}>{player.isVerified ? "Верифицирован" : "Не верифицирован"}</SmallBadge>
                <SmallBadge tone={player.onboardingCompleted ? "success" : "warning"}>{player.onboardingCompleted ? "Профиль заполнен" : "Онбординг не завершён"}</SmallBadge>
                {dirty ? <SmallBadge tone="warning">Есть несохранённые изменения</SmallBadge> : null}
              </div>
            </div>
          </div>
          <div className="max-w-sm">
            <button
              type="button"
              onClick={() => {
                if (selfDeactivationForbidden) return;
                setStatusError(null);
                setStatusDialogOpen(true);
              }}
              disabled={dirty || selfDeactivationForbidden}
              title={
                selfDeactivationForbidden
                  ? "Нельзя деактивировать собственный аккаунт администратора"
                  : dirty
                    ? "Сначала сохраните или отмените изменения профиля"
                    : undefined
              }
              className={`inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg px-5 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40 ${player.accountStatus === "active" ? "bg-red-600" : "bg-emerald-700"}`}
            >
              {player.accountStatus === "active" ? <ShieldOff className="h-4 w-4" /> : <ShieldCheck className="h-4 w-4" />}
              {player.accountStatus === "active" ? "Деактивировать" : "Восстановить аккаунт"}
            </button>
            {selfDeactivationForbidden ? (
              <p className="mt-2 text-xs leading-5 text-ink/55">Собственный аккаунт администратора нельзя деактивировать.</p>
            ) : null}
          </div>
        </div>
      </header>

      {notice ? <MessagePanel tone="success" title="Готово" detail={notice} /> : null}
      {error ? <MessagePanel tone="danger" title="Операция не выполнена" detail={error} /> : null}

      <form onSubmit={saveProfile} className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]">
        <div className="space-y-5">
          <EditorSection title="Основные данные" icon={<UserRoundCog className="h-5 w-5" />}>
            <div className="grid gap-4 md:grid-cols-2">
              <Field label="Имя">
                <input value={form.name ?? ""} onChange={(event) => setField("name", event.target.value)} className={inputClass} maxLength={40} />
              </Field>
              <Field label="Возраст">
                <input type="number" min={18} max={100} value={form.age ?? ""} onChange={(event) => setField("age", event.target.value ? Number(event.target.value) : null)} className={inputClass} />
              </Field>
              <Field label="Пол">
                <select value={form.gender ?? ""} onChange={(event) => setField("gender", (event.target.value || null) as Gender | null)} className={inputClass}>
                  <option value="">Не указан</option>
                  {Object.entries(GENDER_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </Field>
              <Field label="Город">
                <select value={form.city ?? ""} onChange={(event) => setField("city", event.target.value || null)} className={inputClass}>
                  <option value="">Не указан</option>
                  {AVAILABLE_CITIES.map((city) => <option key={city} value={city}>{city}</option>)}
                </select>
              </Field>
              <Field label="Предпочтительный формат">
                <select value={form.preferredPlayFormat} onChange={(event) => setField("preferredPlayFormat", event.target.value as PlayFormat)} className={inputClass}>
                  {Object.entries(PLAY_FORMAT_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </Field>
              <Field label="Предпочтительное покрытие">
                <select value={form.preferredSurface} onChange={(event) => setField("preferredSurface", event.target.value as Surface)} className={inputClass}>
                  {Object.entries(SURFACE_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </Field>
              <label className="flex min-h-12 items-center justify-between rounded-lg border border-black/10 bg-[#fbfaf6] px-3 text-sm font-semibold text-ink">
                Ищет игру
                <input type="checkbox" checked={form.isLookingForGame} onChange={(event) => setField("isLookingForGame", event.target.checked)} className="h-5 w-5 accent-court" />
              </label>
            </div>
            <Field label="О себе">
              <textarea value={form.bio ?? ""} onChange={(event) => setField("bio", event.target.value)} className={`${inputClass} min-h-28 py-3`} maxLength={220} />
            </Field>
          </EditorSection>

          <EditorSection title="Районы">
            <p className="mb-3 text-sm text-ink/60">Первый выбранный район станет основным.</p>
            <div className="max-h-72 overflow-y-auto rounded-lg border border-black/10 bg-[#fbfaf6] p-3">
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {DISTRICT_OPTIONS.map((district) => {
                  const checked = form.preferredDistricts.includes(district);
                  return (
                    <label key={district} className={`flex cursor-pointer items-center gap-2 rounded-md px-3 py-2 text-sm ${checked ? "bg-mint font-semibold" : "bg-white"}`}>
                      <input type="checkbox" checked={checked} onChange={() => toggleDistrict(form, district, setField)} className="h-4 w-4 accent-court" />
                      {DISTRICT_LABELS[district]}
                    </label>
                  );
                })}
              </div>
            </div>
          </EditorSection>

          <EditorSection title="Спорт и уровень">
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {SPORT_OPTIONS.map((sport) => {
                const checked = form.preferredSports.includes(sport);
                return (
                  <div key={sport} className={`rounded-lg border p-3 ${checked ? "border-court/40 bg-mint" : "border-black/10 bg-[#fbfaf6]"}`}>
                    <label className="flex cursor-pointer items-center gap-2 text-sm font-semibold">
                      <input type="checkbox" checked={checked} disabled={checked && form.preferredSports.length === 1} onChange={() => toggleSport(form, sport, setField)} className="h-4 w-4 accent-court disabled:opacity-40" />
                      {SPORT_LABELS[sport]}
                    </label>
                    {checked ? (
                      <label className="mt-3 flex items-center gap-3 text-xs text-ink/60">
                        Уровень
                        <input type="number" min={1} max={10} value={form.sportLevels[sport] ?? ""} onChange={(event) => setSportLevel(form, sport, event.target.value ? Number(event.target.value) : null, setField)} className="h-9 w-20 rounded-md border border-black/10 bg-white px-2 text-sm font-semibold text-ink" />
                      </label>
                    ) : null}
                  </div>
                );
              })}
            </div>
          </EditorSection>

          <EditorSection title="Доступность" icon={<Clock3 className="h-5 w-5" />}>
            <div className="space-y-2">
              {DAY_OPTIONS.map((day) => {
                const selected = form.availabilityByDay[day] ?? [];
                return (
                  <div key={day} className="grid gap-2 rounded-lg bg-[#fbfaf6] p-3 sm:grid-cols-[4rem_minmax(0,1fr)] sm:items-center">
                    <div className="text-sm font-bold text-ink">{DAY_LABELS[day]}</div>
                    <div className="grid grid-cols-3 gap-2">
                      {TIME_RANGE_OPTIONS.map((timeRange) => (
                        <label key={timeRange} className={`cursor-pointer rounded-md px-2 py-2 text-center text-xs font-semibold ${selected.includes(timeRange) ? "bg-court text-white" : "bg-white text-ink/60"}`}>
                          <input type="checkbox" className="sr-only" checked={selected.includes(timeRange)} onChange={() => toggleAvailability(form, day, timeRange, setField)} />
                          {TIME_RANGE_LABELS[timeRange]}
                        </label>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </EditorSection>

          <EditorSection title="Медиа-ссылки">
            <div className="grid gap-4 md:grid-cols-2">
              <Field label="URL аватара">
                <input type="url" value={form.avatarUrl ?? ""} onChange={(event) => setField("avatarUrl", event.target.value || null)} className={inputClass} placeholder="https://…" />
              </Field>
              <div className="hidden md:block" />
              <Field label="Фотографии — один URL на строку">
                <textarea value={form.profilePhotoUrls.join("\n")} onChange={(event) => setField("profilePhotoUrls", lines(event.target.value))} className={`${inputClass} min-h-28 py-3`} placeholder="https://…" />
              </Field>
              <Field label="Видео — один URL на строку">
                <textarea value={form.profileVideoUrls.join("\n")} onChange={(event) => setField("profileVideoUrls", lines(event.target.value))} className={`${inputClass} min-h-28 py-3`} placeholder="https://…" />
              </Field>
            </div>
            <p className="mt-3 text-xs text-ink/50">Модератор может изменить только существующие URL. Загрузка новых файлов здесь не выполняется.</p>
          </EditorSection>

          <div className="sticky bottom-4 z-10 flex flex-col gap-2 rounded-lg border border-black/10 bg-white/95 p-3 shadow-[0_10px_30px_rgba(17,38,29,0.18)] backdrop-blur sm:flex-row sm:items-center sm:justify-between">
            <div className="text-sm text-ink/60">{dirty ? "Изменения ещё не сохранены" : "Все изменения сохранены"}</div>
            <div className="flex gap-2">
              {dirty ? <button type="button" onClick={() => setForm(toEditableProfile(player))} className="h-11 rounded-lg bg-black/5 px-4 text-sm font-semibold text-ink">Отменить</button> : null}
              <button type="submit" disabled={!dirty || saving} className="inline-flex h-11 items-center justify-center gap-2 rounded-lg bg-ink px-5 text-sm font-semibold text-white disabled:opacity-40">
                <Save className="h-4 w-4" /> {saving ? "Сохраняем…" : "Сохранить профиль"}
              </button>
            </div>
          </div>
        </div>

        <aside className="space-y-5">
          <EditorSection title="Системные данные" icon={<ShieldCheck className="h-5 w-5" />}>
            <dl className="space-y-3 text-sm">
              <SystemRow label="ID" value={player.id} mono />
              <SystemRow label="Email" value={player.email} />
              <SystemRow label="Создан" value={formatDateTime(player.createdAt)} />
              <SystemRow label="Обновлён" value={formatDateTime(player.updatedAt)} />
              <SystemRow label="Последняя активность" value={formatDateTime(player.lastActiveAt)} />
              <SystemRow label="Деактивирован" value={formatDateTime(player.deactivatedAt)} />
              {player.deactivationReason ? <SystemRow label="Причина" value={player.deactivationReason} /> : null}
            </dl>
          </EditorSection>

          <EditorSection title="История модерации" icon={<History className="h-5 w-5" />}>
            {auditLogs.length === 0 ? (
              <div className="text-sm text-ink/50">Действий модераторов пока нет.</div>
            ) : (
              <div className="space-y-3">
                {auditLogs.map((log) => <AuditRow key={log.id} log={log} />)}
              </div>
            )}
          </EditorSection>
        </aside>
      </form>

      {statusDialogOpen && !selfDeactivationForbidden ? (
        <StatusDialog
          player={player}
          reason={statusReason}
          onReasonChange={setStatusReason}
          onClose={() => {
            if (!statusSaving) {
              setStatusDialogOpen(false);
              setStatusReason("");
              setStatusError(null);
            }
          }}
          onConfirm={() => void changeStatus()}
          saving={statusSaving}
          error={statusError}
        />
      ) : null}
    </div>
  );
}

function StatusDialog({ player, reason, onReasonChange, onClose, onConfirm, saving, error }: {
  player: AdminPlayer;
  reason: string;
  onReasonChange: (value: string) => void;
  onClose: () => void;
  onConfirm: () => void;
  saving: boolean;
  error: string | null;
}) {
  const deactivate = player.accountStatus === "active";
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/45 p-4 sm:items-center" role="dialog" aria-modal="true" aria-labelledby="status-dialog-title">
      <div className="w-full max-w-lg rounded-xl bg-white p-5 shadow-2xl">
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className={`inline-flex h-10 w-10 items-center justify-center rounded-full ${deactivate ? "bg-red-100 text-red-700" : "bg-emerald-100 text-emerald-700"}`}>
              {deactivate ? <ShieldOff className="h-5 w-5" /> : <ShieldCheck className="h-5 w-5" />}
            </div>
            <h2 id="status-dialog-title" className="mt-3 text-xl font-bold text-ink">{deactivate ? "Деактивировать аккаунт?" : "Восстановить аккаунт?"}</h2>
          </div>
          <button type="button" onClick={onClose} disabled={saving} className="rounded-md p-2 text-ink/50 hover:bg-black/5" aria-label="Закрыть"><X className="h-5 w-5" /></button>
        </div>
        <p className="mt-3 text-sm leading-6 text-ink/65">
          {deactivate
            ? `Игрок ${player.email} потеряет доступ, активные сессии и поиски будут закрыты.`
            : `Доступ для ${player.email} будет восстановлен. Закрытые ранее поиски не включатся автоматически.`}
        </p>
        <Field label="Причина — обязательно">
          <textarea autoFocus value={reason} onChange={(event) => onReasonChange(event.target.value)} className={`${inputClass} min-h-24 py-3`} minLength={3} maxLength={500} placeholder="Опишите основание решения" />
        </Field>
        {error ? <div className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700" role="alert">{error}</div> : null}
        <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button type="button" onClick={onClose} disabled={saving} className="h-11 rounded-lg bg-black/5 px-4 text-sm font-semibold text-ink">Отмена</button>
          <button type="button" onClick={onConfirm} disabled={saving || reason.trim().length < 3} className={`h-11 rounded-lg px-5 text-sm font-bold text-white disabled:opacity-40 ${deactivate ? "bg-red-600" : "bg-emerald-700"}`}>
            {saving ? "Выполняем…" : deactivate ? "Да, деактивировать" : "Да, восстановить"}
          </button>
        </div>
      </div>
    </div>
  );
}

function EditorSection({ title, icon, children }: { title: string; icon?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-black/10 bg-white p-4 shadow-[0_10px_30px_rgba(17,38,29,0.06)]">
      <h2 className="mb-4 flex items-center gap-2 text-base font-bold text-ink">{icon ? <span className="text-court">{icon}</span> : null}{title}</h2>
      {children}
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="block"><span className="mb-2 block text-xs font-semibold uppercase tracking-[0.14em] text-ink/50">{label}</span>{children}</label>;
}

function SystemRow({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return <div><dt className="text-xs text-ink/45">{label}</dt><dd className={`mt-1 break-words font-semibold text-ink ${mono ? "font-mono text-xs" : ""}`}>{value}</dd></div>;
}

function AuditRow({ log }: { log: AdminPlayerAuditLog }) {
  return (
    <article className="rounded-lg bg-[#fbfaf6] p-3">
      <div className="text-sm font-bold text-ink">{auditActionLabel(log.action)}</div>
      <div className="mt-1 text-xs text-ink/55">{formatDateTime(log.createdAt)} · {log.actorEmail}</div>
      {log.reason ? <div className="mt-2 text-sm leading-5 text-ink/70">{log.reason}</div> : null}
      {log.action === "PROFILE_UPDATED" ? <div className="mt-2 text-xs font-semibold text-court">Изменено: {changedKeys(log.before, log.after).join(", ") || "профиль"}</div> : null}
    </article>
  );
}

function MessagePanel({ tone, title, detail, children }: { tone: "success" | "danger"; title: string; detail: string; children?: React.ReactNode }) {
  const success = tone === "success";
  return (
    <div className={`rounded-lg border p-4 ${success ? "border-emerald-200 bg-emerald-50 text-emerald-800" : "border-red-200 bg-red-50 text-red-700"}`} role={success ? "status" : "alert"}>
      <div className="flex items-center gap-2 font-bold">{success ? <CheckCircle2 className="h-5 w-5" /> : <AlertCircle className="h-5 w-5" />}{title}</div>
      <div className="mt-1 text-sm opacity-80">{detail}</div>
      {children}
    </div>
  );
}

function AccountStatusBadge({ status }: { status: AdminPlayer["accountStatus"] }) {
  return <SmallBadge tone={status === "active" ? "success" : "danger"}>{status === "active" ? "Аккаунт активен" : "Аккаунт деактивирован"}</SmallBadge>;
}

function SmallBadge({ tone, children }: { tone: "success" | "warning" | "danger" | "muted"; children: React.ReactNode }) {
  const styles = { success: "bg-emerald-100 text-emerald-700", warning: "bg-amber-100 text-amber-800", danger: "bg-red-100 text-red-700", muted: "bg-black/5 text-ink/60" };
  return <span className={`rounded-full px-2.5 py-1 text-[11px] font-bold ${styles[tone]}`}>{children}</span>;
}

function EditorSkeleton() {
  return <div className="space-y-5" aria-label="Загрузка карточки"><div className="h-40 animate-pulse rounded-lg bg-white/70" /><div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]"><div className="h-[42rem] animate-pulse rounded-lg bg-white/70" /><div className="h-80 animate-pulse rounded-lg bg-white/70" /></div></div>;
}

function toEditableProfile(player: AdminPlayer): EditableProfile {
  return {
    name: player.name,
    age: player.age,
    gender: player.gender,
    city: player.city,
    district: player.district,
    preferredDistricts: player.preferredDistricts ?? [],
    tennisLevel: player.tennisLevel,
    preferredSports: player.preferredSports ?? [],
    sportLevels: player.sportLevels ?? {},
    preferredPlayFormat: player.preferredPlayFormat,
    preferredSurface: player.preferredSurface,
    bio: player.bio,
    avatarUrl: player.avatarUrl,
    profilePhotoUrls: player.profilePhotoUrls ?? [],
    profileVideoUrls: player.profileVideoUrls ?? [],
    availableDays: player.availableDays ?? [],
    availableTimeRanges: player.availableTimeRanges ?? [],
    availabilityByDay: player.availabilityByDay ?? {},
    isLookingForGame: player.isLookingForGame
  };
}

function normalizeProfileForSave(form: EditableProfile): EditableProfile {
  const availabilityByDay = Object.fromEntries(Object.entries(form.availabilityByDay).filter(([, ranges]) => Array.isArray(ranges) && ranges.length > 0));
  const preferredDistricts = form.preferredDistricts;
  return {
    ...form,
    name: form.name?.trim() || null,
    city: form.city?.trim() || null,
    bio: form.bio?.trim() || null,
    avatarUrl: form.avatarUrl?.trim() || null,
    district: preferredDistricts[0] ?? null,
    preferredDistricts,
    tennisLevel: form.preferredSports.length > 0 ? form.sportLevels[form.preferredSports[0]] ?? form.tennisLevel : null,
    profilePhotoUrls: form.profilePhotoUrls.map((url) => url.trim()).filter(Boolean),
    profileVideoUrls: form.profileVideoUrls.map((url) => url.trim()).filter(Boolean),
    availabilityByDay,
    availableDays: Object.keys(availabilityByDay),
    availableTimeRanges: Array.from(new Set(Object.values(availabilityByDay).flatMap((ranges) => ranges ?? [])))
  };
}

function toggleDistrict(form: EditableProfile, district: string, setField: <Key extends keyof EditableProfile>(key: Key, value: EditableProfile[Key]) => void) {
  const next = form.preferredDistricts.includes(district) ? form.preferredDistricts.filter((item) => item !== district) : [...form.preferredDistricts, district];
  setField("preferredDistricts", next);
  setField("district", next[0] ?? null);
}

function toggleSport(form: EditableProfile, sport: Sport, setField: <Key extends keyof EditableProfile>(key: Key, value: EditableProfile[Key]) => void) {
  const nextSports = form.preferredSports.includes(sport) ? form.preferredSports.filter((item) => item !== sport) : [...form.preferredSports, sport];
  const nextLevels = { ...form.sportLevels };
  if (nextSports.includes(sport) && nextLevels[sport] == null) nextLevels[sport] = 5;
  if (!nextSports.includes(sport)) delete nextLevels[sport];
  setField("preferredSports", nextSports);
  setField("sportLevels", nextLevels);
}

function setSportLevel(form: EditableProfile, sport: Sport, level: number | null, setField: <Key extends keyof EditableProfile>(key: Key, value: EditableProfile[Key]) => void) {
  setField("sportLevels", { ...form.sportLevels, [sport]: level });
  if (sport === form.preferredSports[0]) setField("tennisLevel", level);
}

function toggleAvailability(form: EditableProfile, day: string, timeRange: string, setField: <Key extends keyof EditableProfile>(key: Key, value: EditableProfile[Key]) => void) {
  const current = form.availabilityByDay[day] ?? [];
  const nextRanges = current.includes(timeRange) ? current.filter((item) => item !== timeRange) : [...current, timeRange];
  const next = { ...form.availabilityByDay, [day]: nextRanges };
  setField("availabilityByDay", next);
  setField("availableDays", Object.entries(next).filter(([, ranges]) => ranges && ranges.length > 0).map(([key]) => key));
  setField("availableTimeRanges", Array.from(new Set(Object.values(next).flatMap((ranges) => ranges ?? []))));
}

function lines(value: string) { return value.split("\n"); }
function formatDateTime(value: string | null) { return value ? new Intl.DateTimeFormat("ru-RU", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Нет данных"; }
function auditActionLabel(action: string) { return ({ PROFILE_UPDATED: "Профиль изменён", ACCOUNT_DEACTIVATED: "Аккаунт деактивирован", ACCOUNT_REACTIVATED: "Аккаунт восстановлен" } as Record<string, string>)[action] ?? action; }
function changedKeys(before: unknown, after: unknown) {
  if (!before || !after || typeof before !== "object" || typeof after !== "object" || Array.isArray(before) || Array.isArray(after)) return [];
  const first = before as Record<string, unknown>;
  const second = after as Record<string, unknown>;
  return Array.from(new Set([...Object.keys(first), ...Object.keys(second)])).filter((key) => JSON.stringify(first[key]) !== JSON.stringify(second[key]));
}
function conflictMessage(status: number) { return status === 409 ? "Карточка уже изменилась в другой сессии. Обновите страницу и повторите действие." : "Запрос завершился ошибкой"; }
function buildStatusNotice(status: AdminPlayer["accountStatus"], effects?: StatusEffects) {
  if (status === "active") return "Аккаунт восстановлен. Игрок снова может войти в приложение.";
  if (!effects) return "Аккаунт деактивирован.";
  return `Аккаунт деактивирован: закрыто поисков — ${effects.searchesClosed}, завершено сессий — ${effects.sessionsRevoked}, отключено push-устройств — ${effects.pushDevicesDisabled}.`;
}

const inputClass = "h-12 w-full rounded-lg border border-black/10 bg-[#fbfaf6] px-3 text-sm font-medium text-ink outline-none transition focus:border-court";
