"use client";

import { useRouter } from "next/navigation";
import { Bell } from "lucide-react";

import { cn } from "@/lib/utils";

export function NotificationCenterButton({
  count,
  href = "/notifications"
}: {
  count: number;
  href?: string;
}) {
  const router = useRouter();

  return (
    <button
      type="button"
      aria-label="Открыть центр уведомлений"
      onClick={() => {
        router.push(href);
      }}
      className={cn(
        "relative flex min-h-12 min-w-12 items-center justify-center rounded-[22px] bg-white/92 shadow-card transition duration-200 active:scale-95 active:translate-y-px",
        count > 0 && "shadow-[0_18px_34px_rgba(220,38,38,0.18)]"
      )}
    >
      <Bell className={cn("h-5 w-5 text-ink transition-transform duration-300", count > 0 && "animate-[bell_wiggle_1.6s_ease-in-out_infinite] text-red-500")} />
      {count > 0 ? (
        <span className="absolute -right-1 -top-1 flex min-h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white">
          {count > 99 ? "99+" : count}
        </span>
      ) : null}
    </button>
  );
}
