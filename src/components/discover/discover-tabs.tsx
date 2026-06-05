"use client";

import { CalendarClock, CalendarDays, Flame, HeartHandshake, Search } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

export function DiscoverTabs({
  upcomingCount = 0,
  incomingLikesCount = 0,
  regularCount = 0,
  guestMode = false
}: {
  upcomingCount?: number;
  incomingLikesCount?: number;
  regularCount?: number;
  guestMode?: boolean;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const current =
    searchParams.get("view") === "upcoming"
      ? "upcoming"
      : searchParams.get("view") === "hot"
      ? "hot"
      : searchParams.get("view") === "seeking"
        ? "seeking"
        : searchParams.get("view") === "likes"
          ? "likes"
          : "swipe";

  function switchTab(view: "upcoming" | "swipe" | "likes" | "seeking" | "hot") {
    const params = new URLSearchParams(searchParams.toString());
    if (view === "swipe") {
      params.delete("view");
    } else {
      params.set("view", view);
    }
    router.replace(`${pathname}?${params.toString()}`);
  }

  return (
    <div className="-mx-1 overflow-x-auto pb-1">
      <div className="flex min-w-max gap-2 px-1">
        {!guestMode ? (
          <button
            type="button"
            onClick={() => switchTab("upcoming")}
            data-discover-tab="upcoming"
            className={`inline-flex items-center gap-2 rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "upcoming" ? "bg-court text-white" : "bg-white/80 text-ink/65"}`}
          >
            <CalendarClock className="h-4 w-4" />
            Ближайшие игры
            <span className={`ml-1 inline-flex min-h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold leading-none ${current === "upcoming" ? "bg-white text-court" : "bg-white text-court"}`}>
              {upcomingCount > 99 ? "99+" : upcomingCount}
            </span>
          </button>
        ) : null}
        <button
          type="button"
          onClick={() => switchTab("swipe")}
          data-discover-tab="swipe"
          className={`inline-flex items-center gap-2 rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "swipe" ? "bg-ink text-white" : "bg-white/80 text-ink/65"}`}
        >
          <Search className="h-4 w-4" />
          Похожие игроки
        </button>
        {!guestMode ? (
          incomingLikesCount > 0 ? (
            <button
              type="button"
              onClick={() => switchTab("likes")}
              data-discover-tab="likes"
              className={`inline-flex items-center gap-2 rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${
                current === "likes" ? "bg-emerald-600 text-white" : "bg-emerald-50 text-emerald-800"
              }`}
            >
              <HeartHandshake className="h-4 w-4" />
              Хотят с тобой сыграть
              <span
                className={`ml-1 inline-flex min-h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold leading-none ${
                  current === "likes" ? "bg-white text-emerald-700" : "bg-white text-emerald-700"
                }`}
              >
                {incomingLikesCount > 99 ? "99+" : incomingLikesCount}
              </span>
            </button>
          ) : null
        ) : null}
        <button
          type="button"
          onClick={() => switchTab("seeking")}
          data-discover-tab="seeking"
          className={`inline-flex items-center gap-2 rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "seeking" ? "bg-clay text-white" : "bg-white/80 text-ink/65"}`}
        >
          <CalendarDays className="h-4 w-4" />
          Регулярно
          {regularCount > 0 ? (
            <span className={`ml-1 inline-flex min-h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold leading-none ${current === "seeking" ? "bg-white text-clay" : "bg-white text-clay"}`}>
              {regularCount > 99 ? "99+" : regularCount}
            </span>
          ) : null}
        </button>
        <button
          type="button"
          onClick={() => switchTab("hot")}
          data-discover-tab="hot"
          className={`inline-flex items-center gap-2 rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "hot" ? "bg-red-500 text-white" : "bg-white/80 text-red-600"}`}
        >
          <Flame className="h-4 w-4" />
          Срочно
        </button>
      </div>
    </div>
  );
}
