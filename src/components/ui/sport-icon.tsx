import { cn } from "@/lib/utils";

import { SPORT_LABELS } from "@/lib/constants";

type Sport = keyof typeof SPORT_LABELS;

export function SportIcon({
  sport,
  className
}: {
  sport: Sport;
  className?: string;
}) {
  const common = cn("h-4 w-4", className);

  switch (sport) {
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
    case "pickleball":
      return (
        <svg viewBox="0 0 24 24" fill="none" className={common} aria-hidden="true">
          <circle cx="15.5" cy="8.5" r="4.5" stroke="currentColor" strokeWidth="1.8" />
          <circle cx="14.2" cy="7.2" r="0.8" fill="currentColor" />
          <circle cx="16.8" cy="7.2" r="0.8" fill="currentColor" />
          <circle cx="14.2" cy="9.8" r="0.8" fill="currentColor" />
          <circle cx="16.8" cy="9.8" r="0.8" fill="currentColor" />
          <path d="M11.5 12.5 6 18m0 0-1 3 3-1 5.5-5.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    default:
      return null;
  }
}
