"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import { Button } from "@/components/ui/button";

export function RespondToSearchButton({
  gameSearchId,
  existingStatus
}: {
  gameSearchId: string;
  existingStatus?: "pending" | "approved" | "rejected" | "withdrawn";
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function respond() {
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
    <Button fullWidth variant="secondary" onClick={respond} disabled={loading}>
      {loading ? "Отправляем..." : "Откликнуться"}
    </Button>
  );
}
