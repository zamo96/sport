export const PENDING_GUEST_ACTION_KEY = "pending-guest-action:v1";

export type PendingGuestAction =
  | {
      type: "discover_like";
      userId: string;
      userName?: string | null;
    }
  | {
      type: "game_search_respond";
      gameSearchId: string;
    };

export function savePendingGuestAction(action: PendingGuestAction) {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(PENDING_GUEST_ACTION_KEY, JSON.stringify(action));
}

export function loadPendingGuestAction() {
  if (typeof window === "undefined") {
    return null;
  }

  const raw = window.localStorage.getItem(PENDING_GUEST_ACTION_KEY);

  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw) as PendingGuestAction;
  } catch {
    return null;
  }
}

export function clearPendingGuestAction() {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.removeItem(PENDING_GUEST_ACTION_KEY);
}
