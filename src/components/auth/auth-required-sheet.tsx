"use client";

import Link from "next/link";
import { LockKeyhole, X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

export function AuthRequiredSheet({
  open,
  title,
  description,
  href,
  onClose
}: {
  open: boolean;
  title: string;
  description: string;
  href: string;
  onClose: () => void;
}) {
  if (!open) {
    return null;
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/45 px-4 pb-6">
      <Panel className="w-full max-w-md space-y-4 rounded-[32px] bg-cream">
        <div className="flex items-start justify-between gap-3">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 rounded-full bg-white px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
              <LockKeyhole className="h-3.5 w-3.5" />
              Нужен email
            </div>
            <div className="text-2xl font-bold text-ink">{title}</div>
            <div className="text-sm leading-6 text-ink/65">{description}</div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-white text-ink/60"
            aria-label="Закрыть"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Button type="button" fullWidth variant="ghost" onClick={onClose}>
            Позже
          </Button>
          <Link
            href={href}
            className="inline-flex min-h-12 w-full items-center justify-center rounded-2xl bg-ink px-4 text-sm font-semibold text-white shadow-card"
          >
            Продолжить
          </Link>
        </div>
      </Panel>
    </div>
  );
}
