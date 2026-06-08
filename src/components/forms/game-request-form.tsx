"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { PlayFormat, type Sport } from "@prisma/client";
import { CalendarDays, PhoneCall, Search } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { SPORT_SEARCH_LABELS } from "@/lib/constants";
import { buildCourtSearchTerms, matchesSearchTerms, normalizeSearchText } from "@/lib/search-text";
import {
  getDefaultDurationMinutes,
  getDefaultPlayersNeeded,
  getSportFormatOptions,
  getSportPlaybook,
  resolveFormatForSport
} from "@/lib/sport-playbook";
import { getSportPlayFormatLabelRu } from "@/components/sport-semantics";
import { SportPicker } from "@/components/forms/sport-picker";
import { CourtsMap } from "@/components/maps/courts-map";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

type MatchOption = {
  id: string;
  otherUserName: string;
};

type CourtOption = {
  id: string;
  name: string;
  address: string;
  phone?: string | null;
  district?: string | null;
  locationLat: number;
  locationLng: number;
  supportedSports?: Sport[];
};

type EditingGameRequest = {
  id: string;
  matchId: string;
  proposedCourtId: string;
  proposedDatetime: string;
  durationMinutes?: number | null;
  levelRangeMin?: number | null;
  levelRangeMax?: number | null;
  sport: Sport;
  format: PlayFormat;
  comment?: string | null;
  status: "pending" | "accepted" | "declined" | "canceled";
};

export function GameRequestForm({
  matches,
  courts,
  defaultMatchId,
  defaultCourtId,
  availableSports,
  defaultSport,
  editingGameRequest
}: {
  matches: MatchOption[];
  courts: CourtOption[];
  defaultMatchId?: string;
  defaultCourtId?: string;
  availableSports: Sport[];
  defaultSport?: Sport;
  editingGameRequest?: EditingGameRequest | null;
}) {
  const router = useRouter();
  const isEditing = Boolean(editingGameRequest);
  const initialSport = editingGameRequest?.sport ?? defaultSport ?? availableSports[0] ?? "tennis";
  const initialFormat = editingGameRequest?.format ?? getSportPlaybook(initialSport).defaultFormat;
  const [proposalMode, setProposalMode] = useState<"match" | "open">(
    isEditing || defaultMatchId || matches.length > 0 ? "match" : "open"
  );
  const [matchId, setMatchId] = useState(editingGameRequest?.matchId ?? defaultMatchId ?? matches[0]?.id ?? "");
  const [sport, setSport] = useState<Sport>(initialSport);
  const [proposedCourtId, setProposedCourtId] = useState(editingGameRequest?.proposedCourtId ?? defaultCourtId ?? courts[0]?.id ?? "");
  const [courtQuery, setCourtQuery] = useState("");
  const [showCourtSuggestions, setShowCourtSuggestions] = useState(false);
  const [proposedDatetime, setProposedDatetime] = useState(() => {
    if (editingGameRequest?.proposedDatetime) {
      return toDatetimeLocalValue(editingGameRequest.proposedDatetime);
    }

    const date = new Date(Date.now() + 24 * 60 * 60 * 1000);
    date.setHours(19, 0, 0, 0);
    return toDatetimeLocalValue(date.toISOString());
  });
  const [format, setFormat] = useState<PlayFormat>(initialFormat);
  const [comment, setComment] = useState(editingGameRequest?.comment ?? "");
  const [levelRangeMin, setLevelRangeMin] = useState(String(editingGameRequest?.levelRangeMin ?? 4));
  const [levelRangeMax, setLevelRangeMax] = useState(String(editingGameRequest?.levelRangeMax ?? 6));
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const searchLabels = SPORT_SEARCH_LABELS[sport];
  const formatOptions = useMemo(() => getSportFormatOptions(sport), [sport]);
  const visibleCourts = useMemo(
    () => courts.filter((court) => !court.supportedSports || court.supportedSports.length === 0 || court.supportedSports.includes(sport)),
    [courts, sport]
  );
  const selectedCourt = useMemo(
    () => visibleCourts.find((court) => court.id === proposedCourtId) ?? null,
    [proposedCourtId, visibleCourts]
  );
  const courtSuggestions = useMemo(() => {
    const normalized = normalizeSearchText(courtQuery);
    if (!normalized) {
      return visibleCourts.slice(0, 6);
    }

    return visibleCourts.filter((court) =>
      matchesSearchTerms(
        buildCourtSearchTerms({
          name: court.name,
          address: court.address,
          district: court.district,
          nearestMetroName: null,
          sports: court.supportedSports ?? []
        }),
        normalized
      )
    ).slice(0, 8);
  }, [courtQuery, visibleCourts]);

  const disabled = useMemo(
    () => !proposedCourtId || !proposedDatetime || (proposalMode === "match" && !matchId),
    [matchId, proposalMode, proposedCourtId, proposedDatetime]
  );

  useEffect(() => {
    if (selectedCourt) {
      setCourtQuery(selectedCourt.name);
    }
  }, [selectedCourt]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      if (isEditing && editingGameRequest) {
        await apiFetch(`/game-requests/${editingGameRequest.id}`, {
          method: "PATCH",
          body: JSON.stringify({
            proposedCourtId,
            proposedDatetime: new Date(proposedDatetime).toISOString(),
            levelRangeMin: Number(levelRangeMin),
            levelRangeMax: Number(levelRangeMax),
            sport,
            format,
            comment
          })
        });
        router.push(`/play/games/${editingGameRequest.id}`);
      } else if (proposalMode === "match") {
        await apiFetch("/game-requests", {
          method: "POST",
          body: JSON.stringify({
            matchId,
            proposedCourtId,
            proposedDatetime: new Date(proposedDatetime).toISOString(),
            levelRangeMin: Number(levelRangeMin),
            levelRangeMax: Number(levelRangeMax),
            sport,
            format,
            comment
          })
        });
        router.push(`/inbox/${matchId}`);
      } else {
        const proposalDate = new Date(proposedDatetime);
        const dayKey = proposalDate.toLocaleDateString("en-US", { weekday: "long" }).toLowerCase();
        const hour = proposalDate.getHours();
        const timeRange = hour < 12 ? "morning" : hour < 18 ? "day" : "evening";
        const now = new Date();
        const diffDays = Math.floor((proposalDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1000));
        const hotWindow =
          diffDays <= 0 ? "today" : diffDays === 1 ? "tomorrow" : diffDays === 2 ? "day_after_tomorrow" : null;

        await apiFetch("/game-searches", {
          method: "POST",
          body: JSON.stringify({
            preferredCourtId: proposedCourtId,
            preferredDays: [dayKey],
            preferredTimeRanges: [timeRange],
            searchType: hotWindow ? "hot" : "regular",
            hotWindow,
            hotStartTime: hotWindow ? proposedDatetime.slice(11, 16) : null,
            durationMinutes: durationMinutesForOpenSearch({ sport }),
            hasCourtBooked: Boolean(proposedCourtId),
            sport,
            selfLevel: null,
            selfLevelUnknown: true,
            desiredLevelMin: Number(levelRangeMin),
            desiredLevelMax: Number(levelRangeMax),
            format,
            playersNeeded: getDefaultPlayersNeeded(sport, format),
            comment: comment || `Открытый поиск на ${proposalDate.toLocaleDateString("ru-RU")} в ${proposalDate.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })}`
          })
        });
        router.push("/play/searches");
      }
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : isEditing ? "Не удалось обновить игру" : "Не удалось отправить предложение");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      <Panel className="space-y-4">
        <Field
          label="Вид спорта"
          action={
            <Link
              href="/profile"
              className="rounded-full bg-white/80 px-3 py-1 text-[11px] font-semibold text-court shadow-[0_8px_20px_rgba(17,38,29,0.06)] transition hover:bg-white"
            >
              Другие виды спорта
            </Link>
          }
        >
          <SportPicker
            value={[sport]}
            options={availableSports}
            onChange={(value) => {
              const nextSport = (value[0] as Sport | undefined) ?? "tennis";
              const nextFormat = resolveFormatForSport(nextSport, format);
              const currentCourt = courts.find((court) => court.id === proposedCourtId);
              setSport(nextSport);
              if (currentCourt?.supportedSports?.length && !currentCourt.supportedSports.includes(nextSport)) {
                setProposedCourtId("");
              }
              setFormat(nextFormat);
            }}
          />
        </Field>

        <Field label="Партнер">
          <div className="space-y-3">
            {!isEditing ? (
              <div className="grid grid-cols-2 gap-2 rounded-[22px] bg-cream p-1.5">
                <button
                  type="button"
                  onClick={() => setProposalMode("match")}
                  className={`rounded-[18px] px-3 py-3 text-sm font-semibold transition ${proposalMode === "match" ? "bg-white text-ink shadow-card" : "text-ink/62"}`}
                >
                  Выбрать партнера
                </button>
                <button
                  type="button"
                  onClick={() => setProposalMode("open")}
                  className={`rounded-[18px] px-3 py-3 text-sm font-semibold transition ${proposalMode === "open" ? "bg-white text-ink shadow-card" : "text-ink/62"}`}
                >
                  Открытый поиск
                </button>
              </div>
            ) : null}

            {proposalMode === "match" ? (
              matches.length > 0 ? (
                <select className="input" value={matchId} onChange={(event) => setMatchId(event.target.value)} disabled={isEditing}>
                  {matches.map((match) => (
                    <option key={match.id} value={match.id}>
                      {match.otherUserName}
                    </option>
                  ))}
                </select>
              ) : (
                <div className="rounded-[20px] bg-cream/80 px-4 py-3 text-sm leading-6 text-ink/68">
                  У тебя пока нет активного чата с партнёром. Можно сразу создать открытый поиск.
                </div>
              )
            ) : (
              <div className="rounded-[20px] bg-cream/80 px-4 py-3 text-sm leading-6 text-ink/68">
                Мы создадим открытый поиск игры с выбранным клубом, датой и видом спорта. На него смогут откликнуться другие игроки.
              </div>
            )}
          </div>
        </Field>

        <Field label={searchLabels.centerLabel}>
          <div className="space-y-3">
            <div className="relative">
              <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/40" />
              <input
                value={courtQuery}
                onChange={(event) => {
                  setCourtQuery(event.target.value);
                  setShowCourtSuggestions(true);
                }}
                onFocus={() => setShowCourtSuggestions(true)}
                onBlur={() => window.setTimeout(() => setShowCourtSuggestions(false), 120)}
                className="input pl-11"
                placeholder={`Найти ${searchLabels.centerLabel.toLowerCase()}`}
              />
              {showCourtSuggestions ? (
                <div className="absolute inset-x-0 top-[calc(100%+0.5rem)] z-20 rounded-[24px] border border-white/70 bg-white/95 p-2 shadow-[0_20px_44px_rgba(17,38,29,0.12)] backdrop-blur">
                  <div className="max-h-96 space-y-1 overflow-y-auto">
                    {courtSuggestions.map((court) => (
                      <button
                        key={court.id}
                        type="button"
                        onMouseDown={(event) => {
                          event.preventDefault();
                          setProposedCourtId(court.id);
                          setCourtQuery(court.name);
                          setShowCourtSuggestions(false);
                        }}
                        className="w-full rounded-[18px] px-3 py-3 text-left transition hover:bg-cream"
                      >
                        <div className="text-sm font-semibold text-ink">{court.name}</div>
                        <div className="mt-1 text-xs leading-5 text-ink/58">{court.address}</div>
                      </button>
                    ))}
                    {courtSuggestions.length === 0 ? (
                      <div className="rounded-[18px] px-3 py-3 text-sm text-ink/55">Ничего не нашли. Попробуй район, метро или название клуба.</div>
                    ) : null}
                  </div>
                </div>
              ) : null}
            </div>
            <Link href={`/play/courts${sport ? `?sport=${sport}` : ""}`} className="inline-flex items-center gap-2 text-sm font-semibold text-court">
              <CalendarDays className="h-4 w-4" />
              Открыть полный поиск центров
            </Link>
          </div>
          {selectedCourt ? (
            <div className="mt-3 space-y-2">
              <div className="rounded-[24px] bg-cream/80 p-3">
                <div className="text-sm font-semibold text-ink">{selectedCourt.name}</div>
                <div className="mt-1 text-xs leading-5 text-ink/60">{selectedCourt.address}</div>
                {selectedCourt.phone ? (
                  <a
                    href={buildPhoneHref(selectedCourt.phone)}
                    className="mt-3 inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-court px-4 py-3 text-sm font-semibold text-white"
                  >
                    <PhoneCall className="h-4 w-4" />
                    Позвонить забронировать
                  </a>
                ) : null}
              </div>
              <CourtsMap courts={[selectedCourt]} compact />
            </div>
          ) : null}
        </Field>

        <Field label="Дата и время">
          <input
            className="input"
            type="datetime-local"
            value={proposedDatetime}
            onChange={(event) => setProposedDatetime(event.target.value)}
          />
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Мин. уровень">
            <input className="input" type="number" min={1} max={10} value={levelRangeMin} onChange={(event) => setLevelRangeMin(event.target.value)} />
          </Field>
          <Field label="Макс. уровень">
            <input className="input" type="number" min={1} max={10} value={levelRangeMax} onChange={(event) => setLevelRangeMax(event.target.value)} />
          </Field>
        </div>

        <Field label="Формат">
          <select className="input" value={format} onChange={(event) => setFormat(event.target.value as PlayFormat)}>
            {formatOptions.map((value) => (
              <option key={value} value={value}>
                {getSportPlayFormatLabelRu(sport, value, { playersNeeded: getDefaultPlayersNeeded(sport, value) })}
              </option>
            ))}
          </select>
        </Field>

        <Field label="Комментарий">
          <textarea
            rows={3}
            value={comment}
            onChange={(event) => setComment(event.target.value)}
            className="input min-h-[100px] resize-none py-3"
            placeholder={`Могу сразу согласовать ${searchLabels.centerLabel.toLowerCase()}.`}
          />
        </Field>
      </Panel>

      <Button type="submit" fullWidth disabled={disabled || loading}>
        {loading
          ? isEditing
            ? "Сохраняем..."
            : "Отправляем..."
          : isEditing
            ? "Сохранить изменения"
            : proposalMode === "match"
              ? "Отправить предложение на игру"
              : "Создать открытый поиск"}
      </Button>

      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
    </form>
  );
}

function durationMinutesForOpenSearch({ sport }: { sport: Sport }) {
  return getDefaultDurationMinutes(sport);
}

function toDatetimeLocalValue(value: string) {
  const date = new Date(value);
  const localDate = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return localDate.toISOString().slice(0, 16);
}

function buildPhoneHref(phone: string) {
  const normalized = phone.replace(/[^\d+]/g, "");
  return `tel:${normalized || phone}`;
}

function Field({
  label,
  action,
  children
}: {
  label: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <div className="mb-2 flex items-center justify-between gap-3">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">{label}</div>
        {action}
      </div>
      {children}
    </label>
  );
}
