"use client";

import { FormEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { PlayFormat, type Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { PLAY_FORMAT_LABELS, SPORT_SEARCH_LABELS } from "@/lib/constants";
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
  district?: string | null;
  locationLat: number;
  locationLng: number;
  supportedSports?: Sport[];
};

export function GameRequestForm({
  matches,
  courts,
  defaultMatchId,
  defaultCourtId,
  availableSports
}: {
  matches: MatchOption[];
  courts: CourtOption[];
  defaultMatchId?: string;
  defaultCourtId?: string;
  availableSports: Sport[];
}) {
  const router = useRouter();
  const [matchId, setMatchId] = useState(defaultMatchId ?? matches[0]?.id ?? "");
  const [sport, setSport] = useState<Sport>(availableSports[0] ?? "tennis");
  const [proposedCourtId, setProposedCourtId] = useState(defaultCourtId ?? courts[0]?.id ?? "");
  const [proposedDatetime, setProposedDatetime] = useState(() => {
    const date = new Date(Date.now() + 24 * 60 * 60 * 1000);
    date.setHours(19, 0, 0, 0);
    return date.toISOString().slice(0, 16);
  });
  const [format, setFormat] = useState<PlayFormat>(PlayFormat.singles);
  const [comment, setComment] = useState("");
  const [levelRangeMin, setLevelRangeMin] = useState("4");
  const [levelRangeMax, setLevelRangeMax] = useState("6");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const searchLabels = SPORT_SEARCH_LABELS[sport];
  const visibleCourts = useMemo(
    () => courts.filter((court) => !court.supportedSports || court.supportedSports.length === 0 || court.supportedSports.includes(sport)),
    [courts, sport]
  );
  const selectedCourt = useMemo(
    () => visibleCourts.find((court) => court.id === proposedCourtId) ?? null,
    [proposedCourtId, visibleCourts]
  );

  const disabled = useMemo(() => !matchId || !proposedCourtId || !proposedDatetime, [matchId, proposedCourtId, proposedDatetime]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
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
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось отправить предложение");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      <Panel className="space-y-4">
        <Field label="Вид спорта">
          <SportPicker
            value={[sport]}
            options={availableSports}
            onChange={(value) => {
              const nextSport = (value[0] as Sport | undefined) ?? "tennis";
              setSport(nextSport);
              setProposedCourtId("");
            }}
          />
        </Field>

        <Field label="Партнер">
          <select className="input" value={matchId} onChange={(event) => setMatchId(event.target.value)}>
            {matches.map((match) => (
              <option key={match.id} value={match.id}>
                {match.otherUserName}
              </option>
            ))}
          </select>
        </Field>

        <Field label={searchLabels.centerLabel}>
          <select className="input" value={proposedCourtId} onChange={(event) => setProposedCourtId(event.target.value)}>
            <option value="">Выбери площадку</option>
            {visibleCourts.map((court) => (
              <option key={court.id} value={court.id}>
                {court.name} · {court.address}
              </option>
            ))}
          </select>
          {selectedCourt ? (
            <div className="mt-3 space-y-2">
              <div className="rounded-[24px] bg-cream/80 p-3">
                <div className="text-sm font-semibold text-ink">{selectedCourt.name}</div>
                <div className="mt-1 text-xs leading-5 text-ink/60">{selectedCourt.address}</div>
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
            {Object.entries(PLAY_FORMAT_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
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
        {loading ? "Отправляем..." : "Отправить предложение на игру"}
      </Button>

      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
    </form>
  );
}

function Field({
  label,
  children
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <div className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">{label}</div>
      {children}
    </label>
  );
}
