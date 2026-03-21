"use client";

import { FormEvent, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { HotSearchWindow, PlayFormat, type GameSearchType, type Sport } from "@prisma/client";
import { Flame } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { HOT_SEARCH_WINDOW_LABELS, PLAY_FORMAT_LABELS, SPORT_SEARCH_LABELS } from "@/lib/constants";
import { hasExplicitSportProfile } from "@/lib/sport-levels";
import { AvailabilityPicker } from "@/components/forms/availability-picker";
import { SportPicker } from "@/components/forms/sport-picker";
import { CourtsMap } from "@/components/maps/courts-map";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

type CourtOption = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  locationLat: number;
  locationLng: number;
  supportedSports?: Sport[];
};

export function GameSearchForm({
  courts,
  initialMode = "regular",
  availableSports,
  profileSports,
  sportLevels
}: {
  courts: CourtOption[];
  initialMode?: GameSearchType;
  availableSports: Sport[];
  profileSports: Sport[];
  sportLevels?: unknown;
}) {
  const router = useRouter();
  const [searchType, setSearchType] = useState<GameSearchType>(initialMode);
  const [hotWindow, setHotWindow] = useState<HotSearchWindow>(HotSearchWindow.today);
  const [hotStartTime, setHotStartTime] = useState("19:00");
  const [durationMinutes, setDurationMinutes] = useState(90);
  const [hasCourtBooked, setHasCourtBooked] = useState(false);
  const [sport, setSport] = useState<Sport>(availableSports[0] ?? "tennis");
  const [preferredCourtId, setPreferredCourtId] = useState("");
  const [preferredDays, setPreferredDays] = useState<string[]>(["wednesday", "saturday"]);
  const [preferredTimeRanges, setPreferredTimeRanges] = useState<string[]>(["evening"]);
  const [format, setFormat] = useState<PlayFormat>(PlayFormat.singles);
  const [playersNeeded, setPlayersNeeded] = useState(1);
  const [comment, setComment] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const searchLabels = SPORT_SEARCH_LABELS[sport];
  const hasSportInProfile = useMemo(
    () => hasExplicitSportProfile(profileSports, sportLevels, sport),
    [profileSports, sport, sportLevels]
  );
  const visibleCourts = useMemo(
    () => courts.filter((court) => !court.supportedSports || court.supportedSports.length === 0 || court.supportedSports.includes(sport)),
    [courts, sport]
  );
  const selectedCourt = useMemo(
    () => visibleCourts.find((court) => court.id === preferredCourtId) ?? null,
    [preferredCourtId, visibleCourts]
  );

  const disabled = useMemo(() => {
    if (preferredTimeRanges.length === 0) {
      return true;
    }

    if (searchType === "regular") {
      return preferredDays.length === 0 || !hasSportInProfile;
    }

    return !hotStartTime || !durationMinutes || !hasSportInProfile;
  }, [durationMinutes, hasSportInProfile, hotStartTime, preferredDays, preferredTimeRanges, searchType]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);

    try {
      await apiFetch("/game-searches", {
        method: "POST",
        body: JSON.stringify({
          preferredCourtId: preferredCourtId || null,
          preferredDays,
          preferredTimeRanges: searchType === "hot" ? [getTimeRangeFromTime(hotStartTime)] : preferredTimeRanges,
          searchType,
          hotWindow: searchType === "hot" ? hotWindow : null,
          hotStartTime: searchType === "hot" ? hotStartTime : null,
          durationMinutes: searchType === "hot" ? durationMinutes : null,
          hasCourtBooked,
          sport,
          format,
          playersNeeded,
          comment
        })
      });
      router.push(searchType === "hot" ? "/discover?view=hot" : "/discover?view=seeking");
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось создать поиск");
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
              setPreferredCourtId("");
              setPlayersNeeded(getDefaultPlayersNeeded(nextSport, format));
            }}
          />
        </Field>

        <Panel className="bg-cream text-sm leading-6 text-ink/72">
          Форма подстраивается под выбранный вид спорта. Сейчас поиск будет создан для: <span className="font-semibold text-ink">{searchLabels.centerLabel.toLowerCase()}</span>.
        </Panel>

        {!hasSportInProfile ? (
          <Panel className="bg-red-50 text-sm leading-6 text-red-700">
            Для поиска по этому виду спорта сначала добавь его в профиль и укажи уровень.
            <Link href="/profile" className="ml-1 font-semibold underline underline-offset-2">
              Открыть профиль
            </Link>
          </Panel>
        ) : null}

        <div className="grid grid-cols-2 gap-3">
          <button
            type="button"
            onClick={() => setSearchType("regular")}
            className={`rounded-[24px] border px-4 py-4 text-left ${searchType === "regular" ? "border-ink bg-ink text-white" : "border-white/60 bg-cream text-ink"}`}
          >
            <div className="text-sm font-bold">Обычный поиск</div>
            <div className={`mt-1 text-xs leading-5 ${searchType === "regular" ? "text-white/80" : "text-ink/60"}`}>
              Несколько дней и спокойный поиск партнера.
            </div>
          </button>
          <button
            type="button"
            onClick={() => setSearchType("hot")}
            className={`rounded-[24px] border px-4 py-4 text-left ${searchType === "hot" ? "border-red-500 bg-red-500 text-white" : "border-white/60 bg-cream text-ink"}`}
          >
            <div className="inline-flex items-center gap-2 text-sm font-bold">
              <Flame className="h-4 w-4" />
              Горячий поиск
            </div>
            <div className={`mt-1 text-xs leading-5 ${searchType === "hot" ? "text-white/80" : "text-ink/60"}`}>
              На сегодня или завтра, когда нужен игрок срочно.
            </div>
          </button>
        </div>

        {searchType === "regular" ? (
          <Field label="Дни и время">
            <AvailabilityPicker
              days={preferredDays}
              timeRanges={preferredTimeRanges}
              onDaysChange={setPreferredDays}
              onTimeRangesChange={setPreferredTimeRanges}
            />
          </Field>
        ) : (
          <div className="space-y-4">
            <Field label="Когда нужен игрок">
              <div className="grid grid-cols-2 gap-3">
                {Object.entries(HOT_SEARCH_WINDOW_LABELS).map(([value, label]) => (
                  <button
                    key={value}
                    type="button"
                    onClick={() => setHotWindow(value as HotSearchWindow)}
                    className={`rounded-[22px] px-4 py-4 text-sm font-semibold ${hotWindow === value ? "bg-red-500 text-white" : "bg-cream text-ink"}`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </Field>

            <div className="grid grid-cols-2 gap-3">
              <Field label="Начало игры">
                <input
                  type="time"
                  value={hotStartTime}
                  onChange={(event) => setHotStartTime(event.target.value)}
                  className="input"
                />
              </Field>
              <Field label="Длительность">
                <select
                  className="input"
                  value={durationMinutes}
                  onChange={(event) => setDurationMinutes(Number(event.target.value))}
                >
                  {[60, 90, 120, 150, 180].map((minutes) => (
                    <option key={minutes} value={minutes}>
                      {minutes} минут
                    </option>
                  ))}
                </select>
              </Field>
            </div>

            <Panel className="bg-cream text-sm leading-6 text-ink/70">
              В горячем поиске показывается точное время начала и длительность. После времени старта объявление автоматически исчезает из списка срочных.
            </Panel>

            <div className="rounded-[24px] bg-red-50 p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold text-ink">{searchLabels.bookedTitle}</div>
                  <div className="mt-1 text-xs leading-5 text-ink/60">
                    {searchLabels.bookedHint}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setHasCourtBooked((current) => !current)}
                  className={`flex h-8 w-14 items-center rounded-full p-1 transition ${hasCourtBooked ? "bg-red-500" : "bg-line"}`}
                >
                  <span
                    className={`h-6 w-6 rounded-full bg-white shadow transition ${hasCourtBooked ? "translate-x-6" : "translate-x-0"}`}
                  />
                </button>
              </div>
            </div>
          </div>
        )}

        <Field label="Формат">
          <select
            className="input"
            value={format}
            onChange={(event) => {
              const nextFormat = event.target.value as PlayFormat;
              setFormat(nextFormat);
              setPlayersNeeded(getDefaultPlayersNeeded(sport, nextFormat));
            }}
          >
            {Object.entries(PLAY_FORMAT_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </Field>

        <Field label={needsLobbyCounter(sport, format) ? "Сколько игроков нужно в лобби" : "Сколько ещё игроков нужно"}>
          <select
            className="input"
            value={playersNeeded}
            onChange={(event) => setPlayersNeeded(Number(event.target.value))}
          >
            {Array.from({ length: sport === "football" ? 12 : 8 }, (_, index) => index + 1).map((count) => (
              <option key={count} value={count}>
                {count} {pluralizePlayers(count)}
              </option>
            ))}
          </select>
          <div className="mt-2 text-xs leading-5 text-ink/55">
            {needsLobbyCounter(sport, format)
              ? "Подходит для футбола, волейбола и парного формата: будешь видеть прогресс набора по откликам."
              : "Если ищешь одного человека, оставь 1."}
          </div>
        </Field>

        <Field label={searchType === "hot" ? searchLabels.centerLabel : `Предпочтительный ${searchLabels.centerLabel.toLowerCase()}`}>
          <select className="input" value={preferredCourtId} onChange={(event) => setPreferredCourtId(event.target.value)}>
            <option value="">{searchLabels.anyCenterLabel}</option>
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

        <Field label="Комментарий">
          <textarea
            rows={3}
            value={comment}
            onChange={(event) => setComment(event.target.value)}
            className="input min-h-[100px] resize-none py-3"
            placeholder={
              searchType === "hot"
                ? searchLabels.hotPlaceholder
                : searchLabels.regularPlaceholder
            }
          />
        </Field>
      </Panel>

      <Button type="submit" fullWidth disabled={disabled || loading}>
        {loading ? (
          "Публикуем..."
        ) : searchType === "hot" ? (
          <span className="inline-flex items-center gap-2">
            <Flame className="h-4 w-4" />
            Опубликовать горячий поиск
          </span>
        ) : (
          "Опубликовать поиск игры"
        )}
      </Button>

      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
    </form>
  );
}

function getTimeRangeFromTime(value: string) {
  const hours = Number(value.split(":")[0] ?? "0");

  if (hours < 12) {
    return "morning";
  }

  if (hours < 18) {
    return "day";
  }

  return "evening";
}

function needsLobbyCounter(sport: Sport, format: PlayFormat) {
  return sport === "football" || sport === "volleyball" || format === PlayFormat.doubles;
}

function getDefaultPlayersNeeded(sport: Sport, format: PlayFormat) {
  if (sport === "football") return 9;
  if (sport === "volleyball") return 5;
  if (format === PlayFormat.doubles) return 3;
  return 1;
}

function pluralizePlayers(value: number) {
  if (value % 10 === 1 && value % 100 !== 11) return "игрок";
  if ([2, 3, 4].includes(value % 10) && ![12, 13, 14].includes(value % 100)) return "игрока";
  return "игроков";
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
