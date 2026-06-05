import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { RegularPairOccurrenceConfirmationStatus } from "@prisma/client";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { DAY_LABELS, SPORT_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { prisma } from "@/lib/prisma";
import { PageShell } from "@/components/layout/page-shell";
import { getSportPlayFormatLabelRu } from "@/components/sport-semantics";
import { LiveRefresh } from "@/components/ui/live-refresh";
import { SectionTitle } from "@/components/ui/section-title";
import { Panel } from "@/components/ui/panel";
import { Avatar } from "@/components/ui/avatar";
import { SportBadge } from "@/components/ui/sport-badge";
import { Button } from "@/components/ui/button";
import { getRegularPairForUser } from "@/server/app-data";
import { updateRegularPairOccurrenceConfirmation } from "@/server/regular-occurrences";
import { leaveRegularPairForUser } from "@/server/regular-pairs";

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

export default async function RegularPairPage({
  params
}: {
  params: { id: string };
}) {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref(`/play/regular/${params.id}`));
  }

  const regularPair = await getRegularPairForUser(user.id, params.id);
  if (!regularPair) {
    notFound();
  }

  const partner = regularPair.createdByUserId === user.id ? regularPair.partnerUser : regularPair.createdByUser;
  const days = normalizeStringArray(regularPair.preferredDays);
  const timeRanges = normalizeStringArray(regularPair.preferredTimeRanges);
  const approvedPlayers = regularPair.gameSearch.responses.filter((response) => response.status === "approved");
  const waitlistPlayers = regularPair.gameSearch.responses.filter(
    (response) => response.status !== "approved" && response.responderUserId !== partner.id
  );
  const upcomingOccurrences = regularPair.occurrences.filter((occurrence) => new Date(occurrence.scheduledAt).getTime() > Date.now());
  const nearestCreatedGame = upcomingOccurrences.find((occurrence) => occurrence.gameRequest);

  async function leaveRegularPairAction() {
    "use server";

    const viewer = await getSessionUser();
    if (!viewer) {
      return;
    }

    const pair = await prisma.$transaction((tx) => leaveRegularPairForUser(tx, params.id, viewer.id));
    if (!pair) {
      return;
    }

    revalidatePath("/play/searches");
    revalidatePath("/discover");
    revalidatePath("/inbox");
    redirect(viewer.id === pair.createdByUserId ? "/play/searches" : "/discover?view=seeking");
  }

  async function updateOccurrenceAction(formData: FormData) {
    "use server";

    const viewer = await getSessionUser();
    if (!viewer) {
      return;
    }

    const occurrenceId = String(formData.get("occurrenceId") ?? "");
    const nextStatus = String(formData.get("status") ?? "");

    if (!occurrenceId || (nextStatus !== "confirmed" && nextStatus !== "declined")) {
      return;
    }

    await prisma.$transaction((tx) =>
      updateRegularPairOccurrenceConfirmation(
        tx,
        occurrenceId,
        viewer.id,
        nextStatus === "confirmed"
          ? RegularPairOccurrenceConfirmationStatus.confirmed
          : RegularPairOccurrenceConfirmationStatus.declined
      )
    );

    revalidatePath(`/play/regular/${params.id}`);
    revalidatePath("/play/searches");
    revalidatePath("/discover");
    revalidatePath("/inbox");
    revalidatePath("/game-requests/my");
  }

  return (
    <PageShell>
      <LiveRefresh intervalMs={10000} />
      <SectionTitle
        eyebrow="Регулярная пара"
        title={`${partner.name ?? "Игрок"} подтвержден(а) на регулярную игру`}
        subtitle="Сначала быстрые действия, ниже состав и запасные игроки. Чат остается отдельным местом для деталей."
      />

      <Panel className="space-y-4">
        <div className="flex items-center gap-3">
          <Avatar src={partner.avatarUrl} alt={partner.name ?? "Игрок"} />
          <div>
            <div className="text-lg font-bold text-ink">{partner.name ?? "Игрок"}</div>
            <div className="text-sm text-ink/60">
              {SPORT_LABELS[regularPair.sport]} ·{" "}
              {getSportPlayFormatLabelRu(regularPair.sport, regularPair.format, {
                playersNeeded: regularPair.gameSearch.playersNeeded
              })}
            </div>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          <SportBadge sport={regularPair.sport} />
          {days.map((day) => (
            <span key={day} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {DAY_LABELS[day as keyof typeof DAY_LABELS]}
            </span>
          ))}
          {timeRanges.map((timeRange) => (
            <span key={timeRange} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]}
            </span>
          ))}
          {regularPair.preferredCourt ? (
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {regularPair.preferredCourt.name}
            </span>
          ) : null}
        </div>

        {regularPair.comment ? (
          <div className="rounded-2xl bg-mint px-4 py-3 text-sm leading-6 text-ink/75">{regularPair.comment}</div>
        ) : null}

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Link href={`/play/proposals/new?matchId=${regularPair.matchId}&sport=${regularPair.sport}${regularPair.preferredCourtId ? `&courtId=${regularPair.preferredCourtId}` : ""}`}>
            <Button fullWidth>Предложить ближайшую игру</Button>
          </Link>
          <Link href={`/inbox/${regularPair.matchId}`}>
            <Button fullWidth variant="secondary">Открыть чат</Button>
          </Link>
        </div>
        <form action={leaveRegularPairAction}>
          <Button fullWidth variant="ghost">
            {regularPair.createdByUserId === user.id ? "Закрыть регулярную пару" : "Выйти из регулярной пары"}
          </Button>
        </form>
      </Panel>

      {nearestCreatedGame?.gameRequest ? (
        <Panel className="mt-4 space-y-3 bg-mint/60">
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Ближайшая игра уже создана</div>
          <div className="text-lg font-bold text-ink">
            {new Date(nearestCreatedGame.gameRequest.proposedDatetime).toLocaleString("ru-RU", {
              day: "2-digit",
              month: "2-digit",
              hour: "2-digit",
              minute: "2-digit"
            })}
          </div>
          <div className="text-sm text-ink/70">
            {nearestCreatedGame.gameRequest.proposedCourt?.name ?? nearestCreatedGame.proposedCourt?.name ?? "Клуб уточняется"}
            {nearestCreatedGame.gameRequest.durationMinutes
              ? ` · ${nearestCreatedGame.gameRequest.durationMinutes} мин`
              : ""}
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Link href={`/play/games/${nearestCreatedGame.gameRequest.id}`}>
              <Button fullWidth>Открыть ближайшую игру</Button>
            </Link>
            <Link href={`/inbox/${regularPair.matchId}`}>
              <Button fullWidth variant="secondary">Открыть чат</Button>
            </Link>
          </div>
        </Panel>
      ) : null}

      {upcomingOccurrences.length > 0 ? (
        <Panel className="mt-4 space-y-4">
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Ближайшие слоты</div>
          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/70">
            Вы здесь подтверждаете ближайшие даты по вашей регулярной паре. Как только оба игрока подтверждают один слот, из него автоматически создаётся ближайшая игра.
          </div>
          <div className="space-y-3">
            {upcomingOccurrences.map((occurrence) => {
              const myConfirmation = occurrence.confirmations.find((item) => item.userId === user.id);
              const partnerConfirmation = occurrence.confirmations.find((item) => item.userId === partner.id);
              const linkedGameHref = occurrence.gameRequest
                ? `/play/games/${occurrence.gameRequest.id}`
                : null;
              return (
                <div key={occurrence.id} className="rounded-3xl bg-white/80 p-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <div className="text-base font-bold text-ink">
                      {new Date(occurrence.scheduledAt).toLocaleString("ru-RU", {
                        day: "2-digit",
                        month: "2-digit",
                        year: "numeric",
                        hour: "2-digit",
                        minute: "2-digit"
                      })}
                    </div>
                    <span className="rounded-full bg-ink px-3 py-2 text-xs font-semibold text-white">
                      {occurrence.status === "confirmed"
                        ? occurrence.gameRequest
                          ? "Игра создана"
                          : "Подтверждено"
                        : occurrence.status === "declined"
                          ? "Кто-то не может"
                          : "Ждёт подтверждения"}
                    </span>
                    {occurrence.proposedCourt ? (
                      <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                        {occurrence.proposedCourt.name}
                      </span>
                    ) : null}
                  </div>
                  <div className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
                    <div className="rounded-2xl bg-mint/55 px-4 py-3 text-sm text-ink/75">
                      Ты: {myConfirmation?.status === "confirmed" ? "подтвердил(а)" : myConfirmation?.status === "declined" ? "не можешь" : "ждёт ответа"}
                    </div>
                    <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/75">
                      {partner.name ?? "Партнёр"}: {partnerConfirmation?.status === "confirmed" ? "подтвердил(а)" : partnerConfirmation?.status === "declined" ? "не может" : "ждёт ответа"}
                    </div>
                  </div>
                  {occurrence.status !== "confirmed" ? (
                    <div className="mt-4 flex flex-col gap-3 sm:flex-row">
                      <form action={updateOccurrenceAction} className="flex-1">
                        <input type="hidden" name="occurrenceId" value={occurrence.id} />
                        <input type="hidden" name="status" value="confirmed" />
                        <Button fullWidth>Смогу</Button>
                      </form>
                      <form action={updateOccurrenceAction} className="flex-1">
                        <input type="hidden" name="occurrenceId" value={occurrence.id} />
                        <input type="hidden" name="status" value="declined" />
                        <Button fullWidth variant="secondary">Не смогу</Button>
                      </form>
                    </div>
                  ) : linkedGameHref ? (
                    <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
                      <Link href={linkedGameHref}>
                        <Button fullWidth>Открыть ближайшую игру</Button>
                      </Link>
                      <Link href={`/inbox/${regularPair.matchId}`}>
                        <Button fullWidth variant="secondary">Открыть чат</Button>
                      </Link>
                    </div>
                  ) : (
                    <div className="mt-4 rounded-2xl bg-mint/55 px-4 py-3 text-sm text-ink/75">
                      Оба игрока уже подтвердили этот слот. Ближайшая игра появится здесь автоматически.
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </Panel>
      ) : null}

      <Panel className="mt-4 space-y-3">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Состав</div>
        <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/70">
          Выбранный игрок закреплен за этим регулярным поиском. Остальным откликнувшимся поиск показывается как уже укомплектованный.
        </div>
        <div className="space-y-3">
          {approvedPlayers.map((response) => (
            <div key={response.id} className="flex items-center gap-3 rounded-2xl bg-mint/55 px-4 py-3">
              <Avatar src={response.responderUser.avatarUrl} alt={response.responderUser.name ?? "Игрок"} />
              <div>
                <div className="text-base font-bold text-ink">{response.responderUser.name ?? "Игрок"}</div>
                <div className="text-sm text-ink/65">Подтвержден(а) на регулярную пару</div>
              </div>
            </div>
          ))}
        </div>
      </Panel>

      {waitlistPlayers.length > 0 ? (
        <Panel className="mt-4 space-y-3">
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Запасные игроки</div>
          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/70">
            Эти игроки уже откликались. Если основной партнер не сможет, можно быстро вернуться к ним без нового поиска.
          </div>
          <div className="space-y-2">
            {waitlistPlayers.slice(0, 6).map((response) => (
              <div key={response.id} className="flex items-center gap-3 rounded-2xl bg-cream px-4 py-3">
                <Avatar src={response.responderUser.avatarUrl} alt={response.responderUser.name ?? "Игрок"} />
                <div>
                  <div className="text-base font-bold text-ink">{response.responderUser.name ?? "Игрок"}</div>
                  <div className="text-sm text-ink/65">Ждет, если понадобится замена</div>
                </div>
              </div>
            ))}
          </div>
        </Panel>
      ) : null}
    </PageShell>
  );
}
