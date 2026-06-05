"use client";

import { CalendarDays, Flame, Search, X } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

import { Button } from "@/components/ui/button";

type TourView = "swipe" | "seeking" | "hot";

const DISCOVER_TOUR_STORAGE_KEY = "discover_guided_tour_seen_v2";
const BUBBLE_WIDTH = 320;

export function DiscoverGuidedTour() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [open, setOpen] = useState(false);
  const [stepIndex, setStepIndex] = useState(0);
  const [targetRect, setTargetRect] = useState<DOMRect | null>(null);
  const [viewportWidth, setViewportWidth] = useState(390);

  const steps = useMemo(
    () =>
      [
        {
          view: "swipe" as const,
          icon: Search,
          title: "Здесь подбираются похожие игроки",
          text: "Карточки уже отсортированы по спорту, уровню, расстоянию и доступности. Здесь можно быстро решить, с кем хочется сыграть."
        },
        {
          view: "seeking" as const,
          icon: CalendarDays,
          title: "Тут игроки ищут игру заранее",
          text: "Это регулярные поиски по дням и времени. Удобно выбирать спокойный сценарий без спешки."
        },
        {
          view: "hot" as const,
          icon: Flame,
          title: "Здесь собраны срочные события",
          text: "Игры на сегодня и завтра, когда нужно быстро найти партнёра. Самые быстрые договорённости начинаются отсюда."
        }
      ] satisfies Array<{ view: TourView; icon: typeof Search; title: string; text: string }>,
    []
  );

  useEffect(() => {
    try {
      if (window.localStorage.getItem(DISCOVER_TOUR_STORAGE_KEY) !== "1") {
        setOpen(true);
      }
    } catch {
      setOpen(true);
    }
  }, []);

  useEffect(() => {
    if (!open) {
      return;
    }

    const expectedView = steps[stepIndex]?.view;
    const currentView =
      searchParams.get("view") === "hot"
        ? "hot"
        : searchParams.get("view") === "seeking"
          ? "seeking"
          : "swipe";

    if (expectedView === currentView) {
      return;
    }

    const params = new URLSearchParams(searchParams.toString());
    if (expectedView === "swipe") {
      params.delete("view");
    } else {
      params.set("view", expectedView);
    }
    router.replace(`${pathname}${params.toString() ? `?${params.toString()}` : ""}`, { scroll: false });
  }, [open, pathname, router, searchParams, stepIndex, steps]);

  useEffect(() => {
    if (!open) {
      return;
    }

    function updateTarget() {
      setViewportWidth(window.innerWidth);
      const target = document.querySelector<HTMLElement>(`[data-discover-tab="${steps[stepIndex]?.view}"]`);
      target?.scrollIntoView({
        behavior: "auto",
        block: "nearest",
        inline: "center"
      });
      setTargetRect(target?.getBoundingClientRect() ?? null);
    }

    const raf = window.requestAnimationFrame(updateTarget);
    const delayedUpdate = window.setTimeout(updateTarget, 80);
    window.addEventListener("resize", updateTarget);
    window.addEventListener("scroll", updateTarget, true);

    return () => {
      window.cancelAnimationFrame(raf);
      window.clearTimeout(delayedUpdate);
      window.removeEventListener("resize", updateTarget);
      window.removeEventListener("scroll", updateTarget, true);
    };
  }, [open, stepIndex, steps]);

  function completeTour() {
    try {
      window.localStorage.setItem(DISCOVER_TOUR_STORAGE_KEY, "1");
    } catch {
      // ignore storage failures
    }
    setOpen(false);
  }

  function goNext() {
    if (stepIndex >= steps.length - 1) {
      completeTour();
      return;
    }
    setStepIndex((current) => current + 1);
  }

  if (!open || !targetRect) {
    return null;
  }

  const step = steps[stepIndex];
  const Icon = step.icon;
  const bubbleLeft = Math.min(Math.max(targetRect.left + targetRect.width / 2 - BUBBLE_WIDTH / 2, 16), viewportWidth - BUBBLE_WIDTH - 16);
  const arrowLeft = Math.min(Math.max(targetRect.left + targetRect.width / 2 - bubbleLeft - 10, 22), BUBBLE_WIDTH - 38);

  return (
    <div className="fixed inset-0 z-[70] bg-ink/16 transition-opacity duration-300">
      <div
        className="pointer-events-none fixed rounded-[24px] border border-white/95 bg-white/[0.02] shadow-[0_20px_48px_rgba(17,38,29,0.12)] ring-2 ring-white/90 transition-all duration-300"
        style={{
          top: Math.max(targetRect.top - 6, 12),
          left: Math.max(targetRect.left - 6, 8),
          width: targetRect.width + 12,
          height: targetRect.height + 12
        }}
      />

      <div
        className="pointer-events-auto fixed w-[320px] max-w-[calc(100vw-32px)] rounded-[28px] border border-[#eadfce] bg-[#fff4e8] p-4 shadow-[0_30px_80px_rgba(17,38,29,0.18)] transition-all duration-300"
        style={{
          top: targetRect.bottom + 18,
          left: bubbleLeft
        }}
      >
        <div
          className="absolute -top-2 h-4 w-4 rotate-45 border-l border-t border-[#eadfce] bg-[#fff4e8]"
          style={{ left: arrowLeft }}
        />

        <div className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 items-start gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white text-court shadow-[0_10px_24px_rgba(17,38,29,0.08)]">
              <Icon className="h-4.5 w-4.5" />
            </div>
            <div className="min-w-0">
              <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-court/90">
                Подсказка {stepIndex + 1} из {steps.length}
              </div>
              <div className="mt-1 text-base font-semibold leading-6 text-ink">{step.title}</div>
            </div>
          </div>
          <button
            type="button"
            onClick={completeTour}
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-white text-ink/60 shadow-[0_10px_24px_rgba(17,38,29,0.08)]"
            aria-label="Закрыть подсказку"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="mt-3 text-sm leading-6 text-ink/82">{step.text}</div>

        <div className="mt-4 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            {steps.map((tourStep, index) => (
              <span
                key={tourStep.view}
                className={`h-2.5 rounded-full transition-all duration-300 ${index === stepIndex ? "w-6 bg-court" : "w-2.5 bg-line"}`}
              />
            ))}
          </div>
          <div className="flex items-center gap-2">
            <Button type="button" variant="ghost" onClick={completeTour}>
              Пропустить
            </Button>
            <Button type="button" onClick={goNext}>
              {stepIndex === steps.length - 1 ? "Понятно" : "Дальше"}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
