"use client";

import { useEffect, useMemo, useRef } from "react";

import { cn } from "@/lib/utils";

const AGES = Array.from({ length: 82 }, (_, index) => 18 + index);

export function AgeRibbonPicker({
  value,
  onChange,
  className
}: {
  value: number;
  onChange: (value: number) => void;
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const selectedRef = useRef<HTMLButtonElement | null>(null);
  const normalizedValue = useMemo(() => (value >= 18 && value <= 99 ? value : 28), [value]);

  useEffect(() => {
    const container = containerRef.current;
    const selected = selectedRef.current;

    if (!container || !selected) {
      return;
    }

    const targetLeft = selected.offsetLeft - container.clientWidth / 2 + selected.clientWidth / 2;
    container.scrollTo({
      left: Math.max(0, targetLeft),
      behavior: "smooth"
    });
  }, [normalizedValue]);

  return (
    <div className={cn("relative overflow-hidden", className)}>
      <div className="pointer-events-none absolute inset-y-0 left-0 z-10 w-8 bg-gradient-to-r from-white/85 to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 z-10 w-8 bg-gradient-to-l from-white/85 to-transparent" />
      <div className="pointer-events-none absolute inset-y-1 left-1/2 z-10 w-14 -translate-x-1/2 rounded-[18px] border border-court/12 bg-court/6 shadow-[0_10px_24px_rgba(20,47,38,0.06)]" />

      <div
        ref={containerRef}
        className="flex snap-x snap-mandatory gap-2 overflow-x-auto rounded-[22px] border border-white/80 bg-white/78 py-1.5 [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden"
      >
        <div className="w-[calc(50%-1.75rem)] shrink-0" />
        {AGES.map((age) => {
          const active = age === normalizedValue;
          return (
            <button
              key={age}
              ref={active ? selectedRef : null}
              type="button"
              onClick={() => onChange(age)}
              className={cn(
                "relative z-20 h-11 min-w-[3.5rem] snap-center rounded-[18px] text-center text-base font-semibold transition-all duration-200",
                active
                  ? "scale-[1.02] bg-[linear-gradient(180deg,rgba(46,114,92,0.96),rgba(20,47,38,0.92))] text-white shadow-[0_12px_24px_rgba(20,47,38,0.18)]"
                  : "bg-transparent text-ink/48 hover:text-ink"
              )}
            >
              {age}
            </button>
          );
        })}
        <div className="w-[calc(50%-1.75rem)] shrink-0" />
      </div>
    </div>
  );
}
