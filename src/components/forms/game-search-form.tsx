"use client";

import { FormEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { HotSearchWindow, PlayFormat, type GameSearchType, type Sport } from "@prisma/client";
import { Flame } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { HOT_SEARCH_WINDOW_LABELS, PLAY_FORMAT_LABELS } from "@/lib/constants";
import { AvailabilityPicker } from "@/components/forms/availability-picker";
import { SportPicker } from "@/components/forms/sport-picker";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

type CourtOption = {
  id: string;
  name: string;
  address: string;
};

export function GameSearchForm({
  courts,
  initialMode = "regular",
  availableSports
}: {
  courts: CourtOption[];
  initialMode?: GameSearchType;
  availableSports: Sport[];
}) {
  const router = useRouter();
  const [searchType, setSearchType] = useState<GameSearchType>(initialMode);
  const [hotWindow, setHotWindow] = useState<HotSearchWindow>(HotSearchWindow.today);
  const [hasCourtBooked, setHasCourtBooked] = useState(false);
  const [sport, setSport] = useState<Sport>(availableSports[0] ?? "tennis");
  const [preferredCourtId, setPreferredCourtId] = useState("");
  const [preferredDays, setPreferredDays] = useState<string[]>(["wednesday", "saturday"]);
  const [preferredTimeRanges, setPreferredTimeRanges] = useState<string[]>(["evening"]);
  const [format, setFormat] = useState<PlayFormat>(PlayFormat.singles);
  const [comment, setComment] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const disabled = useMemo(() => {
    if (preferredTimeRanges.length === 0) {
      return true;
    }

    if (searchType === "regular") {
      return preferredDays.length === 0;
    }

    return false;
  }, [preferredDays, preferredTimeRanges, searchType]);

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
          preferredTimeRanges,
          searchType,
          hotWindow: searchType === "hot" ? hotWindow : null,
          hasCourtBooked,
          sport,
          format,
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
            onChange={(value) => setSport((value[0] as Sport | undefined) ?? "tennis")}
          />
        </Field>

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

            <Field label="Интервал времени">
              <AvailabilityPicker
                days={[]}
                timeRanges={preferredTimeRanges}
                onDaysChange={() => undefined}
                onTimeRangesChange={setPreferredTimeRanges}
                hideDays
              />
            </Field>

            <div className="rounded-[24px] bg-red-50 p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold text-ink">Корт уже есть</div>
                  <div className="mt-1 text-xs leading-5 text-ink/60">
                    Включи, если площадка уже найдена или забронирована и нужен только игрок.
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
          <select className="input" value={format} onChange={(event) => setFormat(event.target.value as PlayFormat)}>
            {Object.entries(PLAY_FORMAT_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </Field>

        <Field label="Предпочтительный корт">
          <select className="input" value={preferredCourtId} onChange={(event) => setPreferredCourtId(event.target.value)}>
            <option value="">Любой корт</option>
            {courts.map((court) => (
              <option key={court.id} value={court.id}>
                {court.name} · {court.address}
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
            placeholder={
              searchType === "hot"
                ? "Игрок сорвался, корт забронирован на вечер, нужен партнер примерно моего уровня."
                : "Ищу быструю игру после работы."
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
