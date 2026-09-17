"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { ArrowRight, MapPin } from "lucide-react";

import { NearbyDistance, NearbyNotice, type NearbyContext } from "@/components/discover/nearby-notice";
import { useLocale } from "@/components/i18n/locale-provider";

export type EmptyDeckSearcher = {
  id: string;
  name: string | null;
  avatarUrl: string | null;
};

export type EmptyDeckCourt = {
  city?: string | null;
  nearby?: NearbyContext | null;
  id: string;
  name: string;
  distanceLabel: string;
  activeSearchesCount: number;
  memberCount: number;
  searchers: EmptyDeckSearcher[];
};

export type EmptyDeckSection = {
  sport: string;
  sportLabel: string;
  total: number;
  courts: EmptyDeckCourt[];
};

export type EmptyDeckInvite = {
  url: string;
  visits: number;
  joined: number;
};

export function EmptyDeck({
  city,
  seenCount,
  sections,
  invite
}: {
  city: string | null;
  seenCount: number;
  sections: EmptyDeckSection[];
  invite: EmptyDeckInvite | null;
}) {
  const { t } = useLocale();
  const isFirstInCity = seenCount === 0;
  const cityLabel = city ?? "";

  return (
    <div className="space-y-4">
      {/* Приговор и действие в одной карточке: приглашение не должно уезжать
          под сгиб на маленьком экране. */}
      <section className="overflow-hidden rounded-[22px] bg-white/90 shadow-card">
        <div className="p-4">
          <h3 className="text-lg font-bold text-ink">
            {isFirstInCity ? t("discover.nearby.empty") : t("discover.empty.seenAll.title")}
          </h3>
          <p className="mt-1 text-sm leading-6 text-ink/65">
            {isFirstInCity
              ? t("discover.empty.firstHere.text", { city: cityLabel })
              : t("discover.empty.seenAll.text", { city: cityLabel, count: seenCount })}
          </p>
        </div>
        {invite ? <InviteStrip invite={invite} city={cityLabel} /> : null}
      </section>

      <NearbyClubSections sections={sections} />
    </div>
  );
}

export function NearbyClubSections({ sections }: { sections: EmptyDeckSection[] }) {
  const nearby = sections.flatMap((section) => section.courts).find((court) => court.nearby)?.nearby;
  return <div className="space-y-3">
    {nearby ? <NearbyNotice nearby={nearby} clubs /> : null}
    {sections.map((section, index) => <ClubRow key={section.sport} section={section} driftSeconds={22 + index * 4} />)}
  </div>;
}

function InviteStrip({ invite, city }: { invite: EmptyDeckInvite; city: string }) {
  const { t } = useLocale();
  const [showsLink, setShowsLink] = useState(true);
  const [copied, setCopied] = useState(false);
  const message = `${t("discover.empty.invite.shareText", { city })} ${invite.url}`;

  useEffect(() => {
    // Ссылку никто не перепечатывает: она нужна на один взгляд, дальше место
    // занимает зря.
    const timer = window.setTimeout(() => setShowsLink(false), 2600);
    return () => window.clearTimeout(timer);
  }, []);

  async function share() {
    if (typeof navigator !== "undefined" && navigator.share) {
      try {
        await navigator.share({ text: message, url: invite.url });
        return;
      } catch {
        // Человек закрыл системный лист — не ошибка, идём копировать.
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

  return (
    <div className="flex items-center gap-3 bg-clay px-4 py-3">
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-semibold text-white">{t("discover.empty.invite.title")}</div>
        <div
          className={`overflow-hidden font-mono text-[11px] text-white/80 transition-all duration-500 ${
            showsLink ? "mt-0.5 max-h-5 opacity-100" : "max-h-0 opacity-0"
          }`}
        >
          <span className="block truncate">{invite.url.replace(/^https?:\/\//, "")}</span>
        </div>
      </div>
      <button
        type="button"
        onClick={share}
        className="shrink-0 rounded-[11px] bg-white px-4 py-2 text-xs font-bold text-clay transition hover:bg-white/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      >
        {copied ? t("discover.empty.invite.copied") : t("discover.empty.invite.share")}
      </button>
    </div>
  );
}

function ClubRow({ section, driftSeconds }: { section: EmptyDeckSection; driftSeconds: number }) {
  const { t } = useLocale();
  const trackRef = useRef<HTMLDivElement | null>(null);
  const originCity = section.courts.find((court) => court.nearby)?.nearby?.originCity ?? section.courts[0]?.city;
  const courtsHref = `/play/courts?sport=${section.sport}${originCity ? `&city=${encodeURIComponent(originCity)}` : ""}`;

  useEffect(() => {
    const track = trackRef.current;

    if (!track || section.courts.length < 3) {
      return;
    }

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return;
    }

    let frame = 0;
    let direction = 1;
    let last = performance.now();
    let stopped = false;

    // Крутим настоящий scrollLeft, а не transform: иначе ряд перестал бы
    // листаться рукой, а палец здесь главнее анимации.
    const maxScroll = () => track.scrollWidth - track.clientWidth;
    const speed = maxScroll() / Math.max(1, driftSeconds);

    function step(now: number) {
      const delta = (now - last) / 1000;
      last = now;

      const limit = maxScroll();
      if (limit <= 0) {
        return;
      }

      track!.scrollLeft += speed * delta * direction;

      if (track!.scrollLeft >= limit - 1) {
        direction = -1;
      } else if (track!.scrollLeft <= 1) {
        direction = 1;
      }

      frame = window.requestAnimationFrame(step);
    }

    // Первое же действие человека выключает дрейф навсегда: возвращать
    // движение после того, как он пролистал сам, значит спорить с ним.
    function stop() {
      if (stopped) {
        return;
      }
      stopped = true;
      window.cancelAnimationFrame(frame);
    }

    frame = window.requestAnimationFrame(step);
    track.addEventListener("pointerdown", stop, { passive: true });
    track.addEventListener("wheel", stop, { passive: true });
    track.addEventListener("touchstart", stop, { passive: true });

    return () => {
      window.cancelAnimationFrame(frame);
      track.removeEventListener("pointerdown", stop);
      track.removeEventListener("wheel", stop);
      track.removeEventListener("touchstart", stop);
    };
  }, [driftSeconds, section.courts.length]);

  return (
    <section className="space-y-2">
      <div className="flex items-baseline justify-between px-1">
        <h4 className="text-sm font-bold text-ink">{section.sportLabel}</h4>
        <Link href={courtsHref} className="text-xs font-semibold text-court hover:underline">
          {t("discover.empty.sportAll", { count: section.total })}
        </Link>
      </div>
      <div ref={trackRef} className="flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {section.courts.map((court) => (
          <ClubTile key={court.id} court={court} />
        ))}
        <Link
          href={courtsHref}
          className="flex w-24 shrink-0 flex-col items-center justify-center gap-1 rounded-[16px] border border-dashed border-line bg-white/55 text-court transition hover:bg-white"
        >
          <ArrowRight className="h-4 w-4" />
          <span className="px-1 text-center text-[11px] font-semibold leading-tight">
            {t("discover.empty.allCourtsTile")}
          </span>
        </Link>
      </div>
    </section>
  );
}

function ClubTile({ court }: { court: EmptyDeckCourt }) {
  const { t } = useLocale();
  const reason =
    court.activeSearchesCount > 0
      ? t("discover.empty.why.searching", { count: court.activeSearchesCount })
      : court.memberCount > 0
        ? t("discover.empty.why.members", { count: court.memberCount })
        : null;

  return (
    <Link
      href={`/play/courts?q=${encodeURIComponent(court.name)}${court.city ? `&city=${encodeURIComponent(court.city)}` : ""}`}
      className="flex w-[168px] shrink-0 flex-col gap-1.5 rounded-[16px] bg-white p-2.5 shadow-card transition hover:-translate-y-0.5"
    >
      <span className="flex items-center gap-2">
        <span className="grid h-7 w-7 shrink-0 place-items-center rounded-[8px] bg-mint text-court">
          <MapPin className="h-3.5 w-3.5" />
        </span>
        <span className="min-w-0">
          <span className="block truncate text-xs font-semibold text-ink">{court.name}</span>
          {court.city ? <span className="block text-[10px] text-ink/60">{court.city}</span> : null}
          <span className="block text-[10px] tabular-nums text-ink/60">{court.nearby ? <NearbyDistance nearby={court.nearby} /> : court.distanceLabel}</span>
        </span>
      </span>

      <span className="flex h-[22px] items-center gap-1.5">
        {court.searchers.length > 0 ? <SearcherFaces searchers={court.searchers} /> : null}
        {court.activeSearchesCount > 0 ? <span className="h-1.5 w-1.5 rounded-full bg-[#3FA37F]" /> : null}
      </span>

      <span className={`truncate text-[10px] ${reason ? "font-semibold text-court" : "text-ink/55"}`}>
        {reason ?? t("discover.empty.why.rent")}
      </span>
    </Link>
  );
}

function SearcherFaces({ searchers }: { searchers: EmptyDeckSearcher[] }) {
  return (
    <span className="flex">
      {searchers.map((searcher) => (
        <span
          key={searcher.id}
          className="-ml-2 grid h-[21px] w-[21px] place-items-center rounded-full border-2 border-white bg-court text-[8px] font-bold text-white first:ml-0"
          title={searcher.name ?? undefined}
        >
          {initials(searcher.name)}
        </span>
      ))}
    </span>
  );
}

function initials(name: string | null) {
  if (!name) {
    return "?";
  }

  return (
    name
      .split(" ")
      .slice(0, 2)
      .map((part) => part.charAt(0))
      .join("")
      .toUpperCase() || "?"
  );
}
