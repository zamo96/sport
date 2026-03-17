import type { Sport } from "@prisma/client";

import { cn } from "@/lib/utils";

export function SportIcon({
  sport,
  className
}: {
  sport: Sport;
  className?: string;
}) {
  const common = cn("h-4 w-4", className);

  switch (sport) {
    case "table_tennis":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <circle cx="8" cy="8" r="4" stroke="currentColor" strokeWidth="1.8" />
          <path d="M12 8h4.5a3.5 3.5 0 0 1 0 7H14" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
          <path d="M8 12v7" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
          <path d="M15 15v5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      );
    case "tennis":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <circle cx="15.5" cy="8.5" r="4.5" stroke="currentColor" strokeWidth="1.8" />
          <path d="M12.5 11.5 6 18m0 0-1.5 4L8.5 20 15 13.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M12.5 5.5 18.5 11.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
      );
    case "padel":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <path d="M14 3c3.3 0 6 2.7 6 6 0 4.4-3.2 8.2-7.5 9L10 22l-2-2 4-2.5C13.8 17 17 13.4 17 9c0-1.7-1.3-3-3-3S11 7.3 11 9c0 2.1 1.1 4.1 2.9 5.2" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          <circle cx="14.5" cy="8.5" r="0.8" fill="currentColor" />
          <circle cx="16.8" cy="8.5" r="0.8" fill="currentColor" />
          <circle cx="14.5" cy="10.8" r="0.8" fill="currentColor" />
          <circle cx="16.8" cy="10.8" r="0.8" fill="currentColor" />
        </svg>
      );
    case "badminton":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <path d="M7 5 12 10m0 0 5-5m-5 5-2 2m2-2 2 2m-4 0 4 4m-4-4-4 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M10 16 6 20m8-4 4 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      );
    case "squash":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <path d="M14.5 4a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9Z" stroke="currentColor" strokeWidth="1.8" />
          <path d="m11.5 10.5-6 6m0 0L4 21l4.5-1.5 6-6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          <circle cx="6.2" cy="6.2" r="1.4" fill="currentColor" />
        </svg>
      );
    case "volleyball":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <circle cx="12" cy="12" r="8" stroke="currentColor" strokeWidth="1.8" />
          <path d="M12 4a11 11 0 0 1 4.5 8A11 11 0 0 1 12 20" stroke="currentColor" strokeWidth="1.5" />
          <path d="M4.8 8.5c2 .2 4.2 1.2 6 3.2 1.8 2 2.5 4.1 2.7 6" stroke="currentColor" strokeWidth="1.5" />
          <path d="M7 17c1.9-1 4.2-1.4 6.8-1.1 2.1.2 4 .9 5.2 1.8" stroke="currentColor" strokeWidth="1.5" />
        </svg>
      );
    case "fitness":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <path d="M3 10h3v4H3v-4Zm15 0h3v4h-3v-4ZM8 8h2v8H8V8Zm6 0h2v8h-2V8Zm-4 3h4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "boxing":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <path d="M8 11c0-2.8 1.8-5 4-5s4 2.2 4 5v2.5A3.5 3.5 0 0 1 12.5 17H11a3 3 0 0 1-3-3V11Z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
          <path d="M9 9V6.5A2.5 2.5 0 0 1 11.5 4H13" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      );
    case "yoga":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <circle cx="12" cy="6" r="2" stroke="currentColor" strokeWidth="1.8" />
          <path d="M12 8v4m0 0-4 3m4-3 4 3m-4 0v5m-5-3h10" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "football":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <circle cx="12" cy="12" r="8" stroke="currentColor" strokeWidth="1.8" />
          <path d="m12 8 2.2 1.6-.8 2.6h-2.8l-.8-2.6L12 8Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
          <path d="m9.5 12.2-2.2 1.4m9.4-1.4 2.1 1.4M10.6 15.2 10 18m4-2.8.6 2.8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      );
    default:
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <circle cx="12" cy="12" r="8" stroke="currentColor" strokeWidth="1.8" />
        </svg>
      );
  }
}
