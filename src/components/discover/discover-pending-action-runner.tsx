"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import { clearPendingGuestAction, loadPendingGuestAction } from "@/lib/pending-guest-action";

export function DiscoverPendingActionRunner() {
  const router = useRouter();
  const startedRef = useRef(false);

  useEffect(() => {
    if (startedRef.current) {
      return;
    }

    const pendingAction = loadPendingGuestAction();

    if (!pendingAction) {
      return;
    }

    const action = pendingAction;

    startedRef.current = true;

    async function run() {
      try {
        if (action.type === "discover_like") {
          const data = await apiFetch<{ match: { id: string } | null }>("/swipes", {
            method: "POST",
            body: JSON.stringify({ toUserId: action.userId, action: "like" })
          });

          clearPendingGuestAction();

          if (data.match?.id) {
            router.push(`/inbox/${data.match.id}`);
            return;
          }

          router.refresh();
          return;
        }

        if (action.type === "game_search_respond") {
          await apiFetch(`/game-searches/${action.gameSearchId}/respond`, {
            method: "POST",
            body: JSON.stringify({ message: "" })
          });

          clearPendingGuestAction();
          router.refresh();
        }
      } catch {
        startedRef.current = false;
      }
    }

    void run();
  }, [router]);

  return null;
}
