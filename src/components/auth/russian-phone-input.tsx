"use client";

import { russianPhoneDigits } from "@/lib/phone";

/**
 * Номер телефона: «+7» стоит отдельно, в поле вводятся только цифры. Номер,
 * вставленный в любом виде («+7 (999) 123-45-67», «8 999…»), сводится к 10 цифрам.
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
        value={value}
        onChange={(event) => onChange(russianPhoneDigits(event.target.value))}
        placeholder="9991234567"
        aria-label={ariaLabel}
        className="h-full min-w-0 flex-1 bg-transparent text-ink outline-none placeholder:text-ink/35"
      />
    </div>
  );
}
