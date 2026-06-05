import Link from "next/link";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { prisma } from "@/lib/prisma";
import { DAY_LABELS, SPORT_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";
import { Button } from "@/components/ui/button";
import { RespondToSearchButton } from "@/components/discover/respond-to-search-button";
import { DiscoverPendingActionRunner } from "@/components/discover/discover-pending-action-runner";

export default async function SearchInvitePage({ params }: { params: { id: string } }) {
  const user = await getSessionUser();

  const gameSearch = await prisma.gameSearch.findFirst({
    where: {
      OR: [{ id: params.id }, { inviteSlug: params.id }]
    },
    include: {
      createdByUser: true,
      preferredCourt: true,
      regularPair: true,
      responses: {
        include: {
          responderUser: true
        },
        orderBy: [{ status: "asc" }, { createdAt: "asc" }]
      }
    }
  });

  if (!gameSearch) {
    return (
      <PageShell>
        <SectionTitle
          eyebrow="Приглашение"
          title="Ой, игра не найдена"
          subtitle="Эта ссылка пока не привязана к активному поиску или организатор ещё не завершил создание карточки."
        />

        <Panel className="space-y-4">
          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/72">
            Попросите организатора создать или заново опубликовать поиск, а затем открыть приглашение ещё раз.
          </div>
          <Link href="/discover?view=seeking" className="block">
            <Button fullWidth>Перейти к поискам</Button>
          </Link>
        </Panel>
      </PageShell>
    );
  }

  const isCreator = user?.id === gameSearch.createdByUserId;
  const myResponse = user ? gameSearch.responses.find((response) => response.responderUserId === user.id) ?? null : null;
  const approvedCount = gameSearch.responses.filter((response) => response.status === "approved").length;
  const pendingCount = gameSearch.responses.filter((response) => response.status === "pending").length;
  const days = Array.isArray(gameSearch.preferredDays)
    ? gameSearch.preferredDays.filter((item): item is string => typeof item === "string")
    : [];
  const timeRanges = Array.isArray(gameSearch.preferredTimeRanges)
    ? gameSearch.preferredTimeRanges.filter((item): item is string => typeof item === "string")
    : [];
  const isRespondable = gameSearch.isActive && gameSearch.status !== "matched" && gameSearch.status !== "closed";
  const authHref = buildGuestAuthHref(`/play/searches/invite/${params.id}`);

  return (
    <PageShell>
      <DiscoverPendingActionRunner />
      <SectionTitle
        eyebrow="Приглашение"
        title="Присоединиться к поиску игры"
        subtitle="Открой карточку, посмотри условия и откликнись прямо по ссылке."
      />

      <div className="space-y-4">
        <Panel className="space-y-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-sm font-semibold uppercase tracking-[0.22em] text-court">Организатор</div>
              <div className="mt-1 text-xl font-bold text-ink">
                {gameSearch.createdByUser.name ?? "Игрок"} · {SPORT_LABELS[gameSearch.sport]}
              </div>
              <div className="mt-1 text-sm text-ink/62">
                {gameSearch.comment?.trim() || "Ищет игроков по этой ссылке и готов быстро собрать состав."}
              </div>
            </div>
            <SportBadge sport={gameSearch.sport} />
          </div>

          <div className="flex flex-wrap gap-2">
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              Собрано {approvedCount} из {Math.max(gameSearch.playersNeeded, 1)}
            </span>
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              Ожидают ответа: {pendingCount}
            </span>
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {gameSearch.searchType === "hot" ? "Срочный поиск" : "Регулярный поиск"}
            </span>
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {gameSearch.format}
            </span>
            {gameSearch.preferredCourt?.name ? (
              <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                {gameSearch.preferredCourt.name}
              </span>
            ) : null}
          </div>

          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/72">
            {[days.map((day) => DAY_LABELS[day as keyof typeof DAY_LABELS]).join(", "), timeRanges.map((range) => TIME_RANGE_LABELS[range as keyof typeof TIME_RANGE_LABELS]).join(", ")]
              .filter(Boolean)
              .join(" · ") || "Время и дни уточнят в чате после отклика."}
          </div>

          {isCreator ? (
            <div className="space-y-3">
              <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-ink/75">
                Это твой поиск. По этой ссылке другие игроки могут открыть карточку и откликнуться.
              </div>
              <Link href={`/play/searches/${gameSearch.id}`} className="block">
                <Button fullWidth>Открыть свой поиск</Button>
              </Link>
            </div>
          ) : isRespondable ? (
            <RespondToSearchButton
              gameSearchId={gameSearch.id}
              responseId={myResponse?.id}
              existingStatus={myResponse?.status}
              searchMatched={gameSearch.status === "matched"}
              authRequiredHref={user ? undefined : authHref}
            />
          ) : (
            <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/72">
              Этот поиск уже не принимает новые отклики.
            </div>
          )}

          {myResponse?.status === "approved" ? (
            <div className="flex flex-wrap gap-2">
              {gameSearch.playersNeeded > 1 ? (
                <Link href={`/play/searches/${gameSearch.id}`}>
                  <Button variant="ghost">Открыть чат состава</Button>
                </Link>
              ) : gameSearch.regularPair ? (
                <Link href={`/play/regular/${gameSearch.regularPair.id}`}>
                  <Button variant="ghost">Открыть регулярную пару</Button>
                </Link>
              ) : null}
            </div>
          ) : null}
        </Panel>
      </div>
    </PageShell>
  );
}
