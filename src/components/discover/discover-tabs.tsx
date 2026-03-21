"use client";

import { Flame } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

export function DiscoverTabs() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const current =
    searchParams.get("view") === "hot" ? "hot" : searchParams.get("view") === "seeking" ? "seeking" : "swipe";

  function switchTab(view: "swipe" | "seeking" | "hot") {
    const params = new URLSearchParams(searchParams.toString());
    if (view === "swipe") {
      params.delete("view");
    } else {
      params.set("view", view);
    }
    router.replace(`${pathname}?${params.toString()}`);
  }

  return (
    <div className="grid grid-cols-3 gap-3 rounded-[28px] bg-white/80 p-2 shadow-card">
      <button
        type="button"
        onClick={() => switchTab("swipe")}
        className={`rounded-[22px] px-4 py-3 text-sm font-semibold ${current === "swipe" ? "bg-ink text-white" : "text-ink/55"}`}
      >
        Свайпы
      </button>
      <button
        type="button"
        onClick={() => switchTab("seeking")}
        className={`rounded-[22px] px-4 py-3 text-sm font-semibold ${current === "seeking" ? "bg-clay text-white" : "text-ink/55"}`}
      >
        🙋 Ищут игру
      </button>
      <button
        type="button"
        onClick={() => switchTab("hot")}
        className={`inline-flex items-center justify-center gap-2 rounded-[22px] px-4 py-3 text-sm font-semibold ${current === "hot" ? "bg-red-500 text-white" : "text-red-600"}`}
      >
        <Flame className={`h-4 w-4 ${current === "hot" ? "text-orange-200" : "text-orange-500"}`} />
        Срочно
      </button>
    </div>
  );
}
