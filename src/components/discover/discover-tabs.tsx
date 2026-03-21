"use client";

import { Flame } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

export function DiscoverTabs({
  incomingLikesCount = 0,
  hotCount = 0
}: {
  incomingLikesCount?: number;
  hotCount?: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const current =
    searchParams.get("view") === "hot"
      ? "hot"
      : searchParams.get("view") === "seeking"
        ? "seeking"
        : searchParams.get("view") === "likes"
          ? "likes"
          : "swipe";

  function switchTab(view: "swipe" | "likes" | "seeking" | "hot") {
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
        <button
          type="button"
          onClick={() => switchTab("swipe")}
          className={`rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "swipe" ? "bg-ink text-white" : "bg-white/80 text-ink/65"}`}
        >
          Похожие
        </button>
        <button
          type="button"
          onClick={() => switchTab("likes")}
          className={`relative rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "likes" ? "bg-court text-white" : "bg-white/80 text-ink/65"}`}
        >
          Хотят с тобой сыграть
          {incomingLikesCount > 0 ? (
            <span className={`absolute -right-1 -top-1 flex min-h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold leading-none ${current === "likes" ? "bg-white text-court" : "bg-red-500 text-white"}`}>
              {incomingLikesCount > 99 ? "99+" : incomingLikesCount}
            </span>
          ) : null}
        </button>
        <button
          type="button"
          onClick={() => switchTab("seeking")}
          className={`rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "seeking" ? "bg-clay text-white" : "bg-white/80 text-ink/65"}`}
        >
          🙋 Ищут игру
        </button>
        <button
          type="button"
          onClick={() => switchTab("hot")}
          className={`relative inline-flex items-center justify-center gap-2 rounded-[22px] px-4 py-3 text-sm font-semibold whitespace-nowrap ${current === "hot" ? "bg-red-500 text-white" : "bg-white/80 text-red-600"}`}
        >
          <Flame className={`h-4 w-4 ${current === "hot" ? "text-orange-200" : "text-orange-500"}`} />
          Срочно
          {hotCount > 0 ? (
            <span className={`absolute -right-1 -top-1 flex min-h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold leading-none ${current === "hot" ? "bg-white text-red-600" : "bg-red-500 text-white"}`}>
              {hotCount > 99 ? "99+" : hotCount}
            </span>
          ) : null}
        </button>
      </div>
    </div>
  );
}
