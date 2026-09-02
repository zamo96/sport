"use client";

import Link from "next/link";
import { useState } from "react";
import { MapPin, Share2, UserPlus } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { useLocale } from "@/components/i18n/locale-provider";

export type EmptyDeckCourt = {
  id: string;
  name: string;
  districtLabel: string | null;
  distanceLabel: string;
};

export type EmptyDeckInvite = {
  url: string;
  visits: number;
  joined: number;
};

export function EmptyDeck({
  city,
  seenCount,
  courts,
  invite
}: {
  city: string | null;
  seenCount: number;
  courts: EmptyDeckCourt[];
  invite: EmptyDeckInvite | null;
}) {
  const { t } = useLocale();
  // Пусто с самого начала и «всех пролистал» — разные ситуации: в первой
  // приглашение единственное, что вообще меняет дело, поэтому идёт первым.
  const isFirstInCity = seenCount === 0;
  const cityLabel = city ?? "";

  const inviteBlock = invite ? <InviteCard invite={invite} city={cityLabel} /> : null;
  const courtsBlock =
    courts.length > 0 ? (
      <section className="space-y-2">
        <div className="flex items-baseline justify-between px-1">
          <h4 className="text-xs font-semibold uppercase tracking-[0.16em] text-ink/55">
            {t("discover.empty.courtsTitle")}
          </h4>
          <Link href="/play/courts" className="text-xs font-semibold text-court hover:underline">
            {t("discover.empty.allCourts")}
          </Link>
        </div>
        <ul className="space-y-2">
          {courts.map((court) => (
            <li key={court.id}>
              <Link
                href={`/play/courts?focus=${court.id}`}
                className="flex items-center gap-3 rounded-[18px] bg-white px-3 py-3 shadow-card transition hover:-translate-y-0.5"
              >
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-[12px] bg-mint text-court">
                  <MapPin className="h-4 w-4" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-semibold text-ink">{court.name}</span>
                  {court.districtLabel ? (
                    <span className="block truncate text-xs text-ink/60">{court.districtLabel}</span>
                  ) : null}
                </span>
                <span className="shrink-0 text-xs font-semibold tabular-nums text-court">{court.distanceLabel}</span>
              </Link>
            </li>
          ))}
        </ul>
      </section>
    ) : null;

  return (
    <div className="space-y-4">
      <Panel className="text-center">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-court">
          <UserPlus className="h-6 w-6" />
        </div>
        <h3 className="mt-4 text-xl font-bold text-ink">
          {isFirstInCity ? t("discover.empty.firstHere.title") : t("discover.empty.seenAll.title")}
        </h3>
        <p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-ink/65">
          {isFirstInCity
            ? t("discover.empty.firstHere.text", { city: cityLabel })
            : t("discover.empty.seenAll.text", { city: cityLabel, count: seenCount })}
        </p>
      </Panel>

      {isFirstInCity ? (
        <>
          {inviteBlock}
          {courtsBlock}
        </>
      ) : (
        <>
          {courtsBlock}
          {inviteBlock}
        </>
      )}
    </div>
  );
}

/** Компактная полоса под колодой, когда карточек мало, но они ещё есть. */
export function ThinDeckInvite({ invite, city }: { invite: EmptyDeckInvite | null; city: string | null }) {
  const { t } = useLocale();

  if (!invite) {
    return null;
  }

  return (
    <div className="rounded-[20px] bg-clay/10 px-4 py-3">
      <div className="text-sm font-semibold text-ink">{t("discover.empty.thin.title")}</div>
      <p className="mt-0.5 text-xs leading-5 text-ink/65">{t("discover.empty.thin.text")}</p>
      <div className="mt-3">
        <ShareButton invite={invite} city={city ?? ""} compact />
      </div>
    </div>
  );
}

function InviteCard({ invite, city }: { invite: EmptyDeckInvite; city: string }) {
  const { t } = useLocale();

  return (
    <section className="rounded-[22px] bg-clay p-5 text-white shadow-glow">
      <h4 className="text-base font-bold">{t("discover.empty.invite.title")}</h4>
      <p className="mt-1 text-sm leading-5 text-white/85">{t("discover.empty.invite.text")}</p>
      <div className="mt-4 flex items-center gap-2 rounded-[14px] bg-white/15 px-3 py-2.5">
        <span className="min-w-0 flex-1 truncate font-mono text-xs font-semibold">
          {invite.url.replace(/^https?:\/\//, "")}
        </span>
        <ShareButton invite={invite} city={city} />
      </div>
      {invite.visits > 0 ? (
        <p className="mt-2.5 text-[11px] text-white/75">
          {t("discover.empty.invite.stats", { visits: invite.visits, joined: invite.joined })}
        </p>
      ) : null}
    </section>
  );
}

function ShareButton({
  invite,
  city,
  compact = false
}: {
  invite: EmptyDeckInvite;
  city: string;
  compact?: boolean;
}) {
  const { t } = useLocale();
  const [copied, setCopied] = useState(false);
  const message = `${t("discover.empty.invite.shareText", { city })} ${invite.url}`;

  async function share() {
    // Системный лист там, где он есть; иначе копируем — на десктопе это
    // единственный способ отдать ссылку.
    if (typeof navigator !== "undefined" && navigator.share) {
      try {
        await navigator.share({ text: message, url: invite.url });
        return;
      } catch {
        // Человек закрыл лист — это не ошибка, продолжаем к копированию.
      }
    }

    try {
      await navigator.clipboard.writeText(invite.url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  const label = copied ? t("discover.empty.invite.copied") : t("discover.empty.invite.share");

  if (compact) {
    return (
      <Button onClick={share} className="w-full">
        <Share2 className="mr-2 inline h-4 w-4" />
        {label}
      </Button>
    );
  }

  return (
    <button
      type="button"
      onClick={share}
      className="shrink-0 rounded-[10px] bg-white/90 px-3 py-1.5 text-xs font-bold text-clay transition hover:bg-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
    >
      {label}
    </button>
  );
}
