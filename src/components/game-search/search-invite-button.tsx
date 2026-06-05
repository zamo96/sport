"use client";

import { useMemo, useState } from "react";
import { Share2 } from "lucide-react";

import { Button } from "@/components/ui/button";

export function SearchInviteButton({
  searchId,
  fullWidth = false
}: {
  searchId: string;
  fullWidth?: boolean;
}) {
  const [copied, setCopied] = useState(false);
  const shareUrl = useMemo(() => {
    if (typeof window === "undefined") {
      return `/play/searches/invite/${searchId}`;
    }

    return new URL(`/play/searches/invite/${searchId}`, window.location.origin).toString();
  }, [searchId]);

  async function share() {
    if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
      await navigator.share({
        title: "Приглашение на поиск игры",
        text: "Присоединяйся к моему поиску игры в TennisSearch.",
        url: shareUrl
      });
      return;
    }

    if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(shareUrl);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    }
  }

  return (
    <Button fullWidth={fullWidth} variant="ghost" onClick={() => void share()}>
      <span className="inline-flex items-center gap-2">
        <Share2 className="h-4 w-4" />
        {copied ? "Ссылка скопирована" : "Пригласить по ссылке"}
      </span>
    </Button>
  );
}
