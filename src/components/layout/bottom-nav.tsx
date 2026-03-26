"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Compass, MessageCircle, Settings2, Trophy, User2 } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { buildGuestAuthHref, loadGuestOnboardingDraft, guestDraftHasProfileBasics } from "@/lib/guest-draft";
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
  const [hasGuestDraft, setHasGuestDraft] = useState(false);
  const [inboxBadgeCount, setInboxBadgeCount] = useState(0);
  const [discoverBadgeCount, setDiscoverBadgeCount] = useState(0);
  const lastBadgeRef = useRef(0);
  const lastDiscoverBadgeRef = useRef(0);
  const audioContextRef = useRef<AudioContext | null>(null);
  const isHidden = hiddenRoutes.some((route) => pathname.startsWith(route));

  function playNotificationBeep() {
    const context = audioContextRef.current;
    if (!context) {
      return;
    }

    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = "sine";
    oscillator.frequency.value = 880;
    gain.gain.value = 0.03;
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start();
    oscillator.stop(context.currentTime + 0.12);
  }

  useEffect(() => {
    function unlockAudio() {
      if (!audioContextRef.current) {
        audioContextRef.current = new window.AudioContext();
      }
    }

    window.addEventListener("pointerdown", unlockAudio, { once: true });
    return () => window.removeEventListener("pointerdown", unlockAudio);
  }, []);

  useEffect(() => {
    const draft = loadGuestOnboardingDraft();
    setHasGuestDraft(Boolean(draft && guestDraftHasProfileBasics(draft)));
  }, [pathname]);

  useEffect(() => {
    if (isHidden) {
      return;
    }

    let active = true;

    async function loadSummary() {
      try {
        const data = await apiFetch<{ inboxBadgeCount: number; discoverBadgeCount: number; notificationSound?: boolean }>("/activity/summary");
        if (active) {
          if (
            (
              (data.inboxBadgeCount > lastBadgeRef.current && lastBadgeRef.current > 0) ||
              (data.discoverBadgeCount > lastDiscoverBadgeRef.current && lastDiscoverBadgeRef.current > 0)
            ) &&
            data.notificationSound !== false
          ) {
            playNotificationBeep();
          }
          lastBadgeRef.current = data.inboxBadgeCount;
          lastDiscoverBadgeRef.current = data.discoverBadgeCount;
          setInboxBadgeCount(data.inboxBadgeCount);
          setDiscoverBadgeCount(data.discoverBadgeCount);
        }
      } catch {
        if (active) {
          lastBadgeRef.current = 0;
          lastDiscoverBadgeRef.current = 0;
          setInboxBadgeCount(0);
          setDiscoverBadgeCount(0);
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
    }).then(() => {
      lastBadgeRef.current = 0;
      setInboxBadgeCount(0);
    }).catch(() => undefined);
  }, [isHidden, pathname]);

  if (isHidden) {
    return null;
  }

  return (
    <nav className="fixed inset-x-0 bottom-0 z-40 mx-auto w-full max-w-md border-t border-white/60 bg-white/90 px-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] pt-3 backdrop-blur">
      <div className="grid grid-cols-5 gap-2">
        {items.map((item) => {
          const href = hasGuestDraft && item.href !== "/discover" ? buildGuestAuthHref(item.href) : item.href;
          const isActive =
            pathname === item.href ||
            (item.href !== "/discover" && pathname.startsWith(item.href));
          const Icon = item.icon;

          return (
            <Link
              key={item.href}
              href={href}
              className={cn(
                "relative flex min-h-14 flex-col items-center justify-center rounded-2xl text-[11px] font-semibold transition",
                isActive ? "bg-ink text-white shadow-glow" : "text-ink/60"
              )}
            >
              {item.href === "/discover" && discoverBadgeCount > 0 ? (
                <span className="absolute right-2 top-1 flex min-h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white">
                  {discoverBadgeCount > 99 ? "99+" : discoverBadgeCount}
                </span>
              ) : null}
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
