"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import { AuthRequiredSheet } from "@/components/auth/auth-required-sheet";
import { Button } from "@/components/ui/button";

export function RespondToSearchButton({
  gameSearchId,
  existingStatus,
  authRequiredHref
}: {
  gameSearchId: string;
  existingStatus?: "pending" | "approved" | "rejected" | "withdrawn";
  authRequiredHref?: string;
}) {
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

  if (existingStatus === "approved") {
    return (
      <Button fullWidth disabled>
        Тебя уже выбрали
      </Button>
    );
  }

  if (existingStatus === "pending") {
    return (
      <Button fullWidth variant="ghost" disabled>
        Отклик отправлен
      </Button>
    );
  }

  return (
    <>
      <Button fullWidth variant="secondary" onClick={respond} disabled={loading}>
        {loading ? "Отправляем..." : "Откликнуться"}
      </Button>
      <AuthRequiredSheet
        open={authPromptOpen}
        onClose={() => setAuthPromptOpen(false)}
        href={authRequiredHref ?? "/auth"}
        title="Подтверди email, чтобы откликнуться"
        description="Так мы сможем показать организатору твой отклик, а тебе прислать ответ и открыть чат, если тебя выберут."
      />
    </>
  );
}
