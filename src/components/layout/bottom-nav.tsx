"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { Compass, MessageCircle, Settings2, Trophy, User2 } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { cn } from "@/lib/utils";

const items = [
  { href: "/discover", label: "Поиск", icon: Compass },
  { href: "/inbox", label: "Мэтчи", icon: MessageCircle },
  { href: "/play/courts", label: "Центры", icon: Trophy },
  { href: "/profile", label: "Профиль", icon: User2 },
  { href: "/settings", label: "Ещё", icon: Settings2 }
];

const hiddenRoutes = ["/auth", "/onboarding", "/offline"];

export function BottomNav() {
  const pathname = usePathname();
  const [inboxBadgeCount, setInboxBadgeCount] = useState(0);
  const isHidden = hiddenRoutes.some((route) => pathname.startsWith(route));

  useEffect(() => {
    if (isHidden) {
      return;
    }

    let active = true;

    async function loadSummary() {
      try {
        const data = await apiFetch<{ inboxBadgeCount: number }>("/activity/summary");
        if (active) {
          setInboxBadgeCount(data.inboxBadgeCount);
        }
      } catch {
        if (active) {
          setInboxBadgeCount(0);
        }
      }
    }

    loadSummary();
    const interval = window.setInterval(loadSummary, 15000);

    return () => {
      active = false;
      window.clearInterval(interval);
    };
  }, [isHidden]);

  useEffect(() => {
    if (isHidden) {
      return;
    }

    if (!pathname.startsWith("/inbox") && !pathname.startsWith("/play/games")) {
      return;
    }

    void apiFetch("/activity/inbox-seen", {
      method: "POST"
    }).then(() => setInboxBadgeCount(0)).catch(() => undefined);
  }, [isHidden, pathname]);

  if (isHidden) {
    return null;
  }

  return (
    <nav className="fixed inset-x-0 bottom-0 z-40 mx-auto w-full max-w-md border-t border-white/60 bg-white/90 px-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] pt-3 backdrop-blur">
      <div className="grid grid-cols-5 gap-2">
        {items.map((item) => {
          const isActive =
            pathname === item.href ||
            (item.href !== "/discover" && pathname.startsWith(item.href));
          const Icon = item.icon;

          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "relative flex min-h-14 flex-col items-center justify-center rounded-2xl text-[11px] font-semibold transition",
                isActive ? "bg-ink text-white shadow-glow" : "text-ink/60"
              )}
            >
              {item.href === "/inbox" && inboxBadgeCount > 0 ? (
                <span className="absolute right-2 top-1 flex min-h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white">
                  {inboxBadgeCount > 99 ? "99+" : inboxBadgeCount}
                </span>
              ) : null}
              <Icon className="mb-1 h-4 w-4" />
              {item.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
