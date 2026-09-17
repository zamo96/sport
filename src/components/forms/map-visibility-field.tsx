"use client";

import { useId, useState } from "react";

export function MapVisibilityField({ checked, onChange, title, hint, infoLabel, extraHint }: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  title: string;
  hint: string;
  infoLabel: string;
  extraHint?: string;
}) {
  const hintId = useId();
  const [showInfo, setShowInfo] = useState(false);
  return (
    <div className="rounded-[20px] bg-cream px-3 py-1">
      <div className="flex items-center gap-1">
        <label className="flex min-h-11 flex-1 cursor-pointer items-center justify-between gap-3">
          <span className="text-sm font-semibold text-ink">{title}</span>
          <input
            type="checkbox"
            role="switch"
            checked={checked}
            onChange={(event) => onChange(event.target.checked)}
            aria-describedby={showInfo ? hintId : undefined}
            className="h-5 w-5 shrink-0 accent-court"
          />
        </label>
        <button
          type="button"
          aria-label={infoLabel}
          aria-expanded={showInfo}
          aria-controls={hintId}
          onClick={() => setShowInfo((current) => !current)}
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-lg text-ink/65 hover:bg-white/60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-court"
        >
          <span aria-hidden="true">ⓘ</span>
        </button>
      </div>
      <div id={hintId} hidden={!showInfo} className="pb-3 text-xs leading-5 text-ink/65">
        <p>{hint}</p>
        {extraHint ? <p className="mt-2">{extraHint}</p> : null}
      </div>
    </div>
  );
}
