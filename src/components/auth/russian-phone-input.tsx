"use client";

import { formatRussianPhoneDigits, russianPhoneDigits } from "@/lib/phone";

/**
 * Номер телефона: «+7» стоит отдельно, вводятся только цифры, а на экране они
 * сразу складываются в «999 123-45-67». Номер, вставленный в любом виде
 * («+7 (999) 123-45-67», «8 999…»), сводится к 10 цифрам.
 */
export function RussianPhoneInput({
  value,
  onChange,
  ariaLabel,
  className = ""
}: {
  value: string;
  onChange: (digits: string) => void;
  ariaLabel?: string;
  className?: string;
}) {
  return (
    <div className={`input flex items-center gap-2 focus-within:border-court ${className}`}>
      <span className="font-semibold text-ink">+7</span>
      <input
        required
        type="tel"
        inputMode="numeric"
        autoComplete="tel-national"
        enterKeyHint="done"
        value={formatRussianPhoneDigits(value)}
        onChange={(event) => onChange(russianPhoneDigits(event.target.value))}
        placeholder="999 123-45-67"
        aria-label={ariaLabel}
        className="h-full min-w-0 flex-1 bg-transparent text-ink outline-none placeholder:text-ink/35"
      />
    </div>
  );
}
