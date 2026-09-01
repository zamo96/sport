"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import { savePendingGuestAction } from "@/lib/pending-guest-action";
import { useLocale } from "@/components/i18n/locale-provider";
import { AuthRequiredSheet } from "@/components/auth/auth-required-sheet";
import { Button } from "@/components/ui/button";

export function RespondToSearchButton({
  gameSearchId,
  responseId,
  existingStatus,
  searchMatched = false,
  authRequiredHref
}: {
  gameSearchId: string;
  responseId?: string;
  existingStatus?: "pending" | "approved" | "rejected" | "withdrawn";
  searchMatched?: boolean;
  authRequiredHref?: string;
}) {
  const { t } = useLocale();
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [authPromptOpen, setAuthPromptOpen] = useState(false);

  async function respond() {
    if (authRequiredHref) {
      setAuthPromptOpen(true);
      return;
    }

    setLoading(true);
    try {
      await apiFetch(`/game-searches/${gameSearchId}/respond`, {
        method: "POST",
        body: JSON.stringify({ message: "" })
      });
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  async function withdraw() {
    if (!responseId) {
      return;
    }
    setLoading(true);
    try {
      await apiFetch(`/game-search-responses/${responseId}`, {
        method: "PATCH",
        body: JSON.stringify({ status: "withdrawn" })
      });
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  if (existingStatus === "approved") {
    return (
      <Button fullWidth disabled>
        {t("discover.respond.approved")}
      </Button>
    );
  }

  if (existingStatus === "pending") {
    return (
      <Button fullWidth variant="ghost" onClick={withdraw} disabled={loading || !responseId}>
        {loading ? t("discover.respond.withdrawing") : t("discover.respond.withdraw")}
      </Button>
    );
  }

  if (existingStatus === "rejected" && searchMatched) {
    return (
      <Button fullWidth variant="ghost" disabled>
        {t("discover.respond.found")}
      </Button>
    );
  }

  return (
    <>
      <Button fullWidth variant="secondary" onClick={respond} disabled={loading}>
        {loading ? t("discover.respond.sending") : t("discover.respond.action")}
      </Button>
      <AuthRequiredSheet
        open={authPromptOpen}
        onClose={() => setAuthPromptOpen(false)}
        href={authRequiredHref ?? "/auth"}
        title={t("discover.respond.authTitle")}
        description={t("discover.respond.authText")}
        onContinue={() => {
          savePendingGuestAction({
            type: "game_search_respond",
            gameSearchId
          });
        }}
      />
    </>
  );
}
