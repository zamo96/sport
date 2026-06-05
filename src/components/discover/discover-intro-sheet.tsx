"use client";

import { CalendarDays, Flame, HeartHandshake, Search, X } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";

import { PENDING_GUEST_ACTION_KEY } from "@/lib/pending-guest-action";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { useLockBodyScroll } from "@/components/ui/use-lock-body-scroll";

const DISCOVER_INTRO_STORAGE_KEY = "discover_intro_seen_v1";

export function DiscoverIntroSheet({
  incomingLikesCount = 0
}: {
  incomingLikesCount?: number;
}) {
  const [open, setOpen] = useState(false);
  const titleId = useId();
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);

  useLockBodyScroll(open);

  useEffect(() => {
    if (!open) {
      return;
    }
    closeButtonRef.current?.focus();
  }, [open]);

  useEffect(() => {
    try {
      if (window.localStorage.getItem(PENDING_GUEST_ACTION_KEY)) {
        return;
      }

      if (window.localStorage.getItem(DISCOVER_INTRO_STORAGE_KEY) !== "1") {
        setOpen(true);
      }
    } catch {
      setOpen(true);
    }
  }, []);

  function closeSheet() {
    try {
      window.localStorage.setItem(DISCOVER_INTRO_STORAGE_KEY, "1");
    } catch {
      // ignore storage failures
    }
    setOpen(false);
  }

  if (!open) {
    return null;
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-end justify-center bg-ink/45 px-4 pb-6 pt-10 backdrop-blur-[2px]"
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.stopPropagation();
          closeSheet();
        }
      }}
    >
      <Panel className="w-full max-w-md space-y-4 rounded-[32px] bg-cream">
        <div className="flex items-start justify-between gap-3">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 rounded-full bg-white px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
              <Search className="h-3.5 w-3.5" />
              Как устроен поиск
            </div>
            <div id={titleId} className="text-2xl font-bold text-ink">
              Сначала смотри игроков, потом выбирай сценарий
            </div>
            <div className="text-sm leading-6 text-ink/65">
              Здесь поиск разделён на несколько простых режимов, чтобы быстро понять, с кем можно сыграть уже сейчас или договориться заранее.
            </div>
          </div>
          <button
            type="button"
            onClick={closeSheet}
            ref={closeButtonRef}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-white text-ink/60"
            aria-label="Закрыть"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="space-y-3">
          <IntroRow
            icon={Search}
            iconClassName="bg-mint text-court"
            title="Похожие игроки"
            text="Карточки уже отсортированы по спорту, уровню, доступности и расстоянию. На карточке есть следующий шаг и причины подбора."
          />
          <IntroRow
            icon={CalendarDays}
            iconClassName="bg-orange-50 text-orange-600"
            title="Регулярно"
            text="Игроки заранее ищут партнёра по дням и времени. Подходит, если хочешь договориться спокойно."
          />
          <IntroRow
            icon={Flame}
            iconClassName="bg-red-50 text-red-600"
            title="Срочно"
            text="Здесь события на сегодня и завтра, когда человек ищет партнёра на ближайшее время."
          />
          <IntroRow
            icon={HeartHandshake}
            iconClassName="bg-rose-50 text-rose-600"
            title="Хотят с тобой сыграть"
            text={
              incomingLikesCount > 0
                ? `Сейчас тебя уже ждут ${incomingLikesCount} входящих лайков. Ответный лайк сразу открывает чат.`
                : "Эта вкладка появится, когда кто-то сам захочет сыграть именно с тобой."
            }
          />
        </div>

        <Button type="button" fullWidth onClick={closeSheet}>
          Понятно
        </Button>
      </Panel>
    </div>
  );
}

function IntroRow({
  icon: Icon,
  iconClassName,
  title,
  text
}: {
  icon: typeof Search;
  iconClassName: string;
  title: string;
  text: string;
}) {
  return (
    <div className="flex items-start gap-3 rounded-[24px] bg-white/78 px-3 py-3">
      <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-full ${iconClassName}`}>
        <Icon className="h-4.5 w-4.5" />
      </div>
      <div className="min-w-0">
        <div className="text-sm font-semibold text-ink">{title}</div>
        <div className="mt-1 text-xs leading-5 text-ink/62">{text}</div>
      </div>
    </div>
  );
}
