"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Compass, MessageCircle, Settings2, Trophy, User2 } from "lucide-react";

import { cn } from "@/lib/utils";

const items = [
  { href: "/discover", label: "Поиск", icon: Compass },
  { href: "/inbox", label: "Мэтчи", icon: MessageCircle },
  { href: "/play/courts", label: "Корты", icon: Trophy },
  { href: "/profile", label: "Профиль", icon: User2 },
  { href: "/settings", label: "Ещё", icon: Settings2 }
];

const hiddenRoutes = ["/auth", "/onboarding", "/offline"];

export function BottomNav() {
  const pathname = usePathname();

  if (hiddenRoutes.some((route) => pathname.startsWith(route))) {
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
                "flex min-h-14 flex-col items-center justify-center rounded-2xl text-[11px] font-semibold transition",
                isActive ? "bg-ink text-white shadow-glow" : "text-ink/60"
              )}
            >
              <Icon className="mb-1 h-4 w-4" />
              {item.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
