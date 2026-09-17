"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { RouteEventTracker } from "@/components/analytics/route-events";

const tracker = new RouteEventTracker();

export function WebActivityTracker() {
  const pathname = usePathname();
  useEffect(() => {
    let storage: Storage | undefined;
    try { storage = window.sessionStorage; } catch { /* Browsers can disable storage. */ }
    void tracker.visit(pathname, {
      now: Date.now(),
      storage,
      send: async events => {
        const response = await fetch("/activity/events", {
          method: "POST",
          credentials: "same-origin",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ events }),
          keepalive: true
        });
        if (!response.ok) return false;
        const result: unknown = await response.json();
        return typeof result === "object" && result !== null && "accepted" in result && Number(result.accepted) > 0;
      }
    });
  }, [pathname]);
  return null;
}
