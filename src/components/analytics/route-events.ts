import type { ClientReportableEventType } from "@/lib/user-events";

type Screen = "onboarding" | "discover" | "play" | "inbox" | "profile" | "settings" | "activity";
type BrowserEvent = { type: ClientReportableEventType; context: { platform: "web"; screen: Screen; step?: number } };
type SessionStore = Pick<Storage, "getItem" | "setItem" | "removeItem">;
const SESSION_KEY = "tennissearch:analytics:last-open";
const SESSION_MS = 30 * 60 * 1000;
const VIEW_COOLDOWN_MS = 60 * 1000;

/** Only fixed screen names are emitted. Paths, player IDs and queries never leave this mapper. */
export function analyticsScreen(pathname: string): Screen | null {
  if (pathname.includes("?") || pathname.includes("#")) return null;
  if (pathname === "/onboarding") return "onboarding";
  if (pathname === "/discover") return "discover";
  if (pathname === "/profile") return "profile";
  if (pathname === "/settings") return "settings";
  if (pathname === "/inbox" || /^\/inbox\/[^/]+$/.test(pathname)) return "inbox";
  if (pathname === "/play" || pathname.startsWith("/play/")) return "play";
  if (pathname === "/activity") return "activity";
  return null;
}

/** One instance per browser tab also survives React StrictMode effect replays. */
export class RouteEventTracker {
  private lastAttempt = new Map<Screen, number>();
  private openedAt = 0;
  private openPending = false;

  async visit(pathname: string, options: { now: number; storage?: SessionStore; send: (events: BrowserEvent[]) => Promise<boolean> }) {
    if (pathname === "/auth") {
      this.openedAt = 0;
      this.lastAttempt.clear();
      try { options.storage?.removeItem(SESSION_KEY); } catch { /* Storage can be disabled. */ }
      return;
    }
    const screen = analyticsScreen(pathname);
    if (!screen) return;
    const previousAttempt = this.lastAttempt.get(screen);
    if (previousAttempt !== undefined && options.now - previousAttempt < VIEW_COOLDOWN_MS) return;
    this.lastAttempt.set(screen, options.now);
    try {
      const storedAt = Number(options.storage?.getItem(SESSION_KEY) ?? 0);
      if (Number.isFinite(storedAt) && storedAt <= options.now) this.openedAt = Math.max(this.openedAt, storedAt);
    } catch { /* In-memory deduplication still works without session storage. */ }
    const context = { platform: "web" as const, screen };
    const events: BrowserEvent[] = [];
    const needsOpen = !this.openPending && (!this.openedAt || options.now - this.openedAt >= SESSION_MS);
    if (needsOpen) { this.openPending = true; events.push({ type: "app_open", context }); }
    if (screen === "discover") events.push({ type: "discover_view", context });
    if (screen === "onboarding") events.push({ type: "onboarding_step", context: { ...context, step: 0 } });
    if (!events.length) return;
    try {
      const accepted = await options.send(events);
      if (accepted && needsOpen) {
        this.openedAt = options.now;
        try { options.storage?.setItem(SESSION_KEY, String(options.now)); } catch { /* Optional persistence only. */ }
      }
    } catch { /* Telemetry must never interrupt navigation or show an error. */ }
    finally { if (needsOpen) this.openPending = false; }
  }
}
