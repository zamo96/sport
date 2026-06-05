import Link from "next/link";
import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { PageShell } from "@/components/layout/page-shell";
import { Avatar } from "@/components/ui/avatar";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";
import { GameRequestCard } from "@/components/chat/game-request-card";
import { LiveRefresh } from "@/components/ui/live-refresh";
import { getMatchesForUser } from "@/server/app-data";

export default async function InboxPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/inbox"));
  }

  if (!user.onboardingCompleted) {
    redirect("/onboarding");
  }

  const matches = await getMatchesForUser(user.id);

  return (
    <PageShell>
      <LiveRefresh intervalMs={10000} />
      <SectionTitle
        eyebrow="Мэтчи"
        title="Переходи от мэтча к игре без лишних шагов."
        subtitle="На карточке видны последнее сообщение и текущий статус договоренности."
      />
      <div className="space-y-4">
        <Panel className="space-y-3">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Поиск игры</div>
              <div className="mt-1 text-base font-bold text-ink">Создай свой поиск и дождись откликов</div>
              <div className="mt-1 text-sm leading-6 text-ink/60">
                Выбери спорт, дни и время. Активные поиски и отклики будут в одном месте.
              </div>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <Link href="/play/searches" className="rounded-2xl bg-cream px-4 py-3 text-center text-sm font-semibold text-ink">
              Мои поиски
            </Link>
            <Link href="/play/searches/new" className="rounded-2xl bg-ink px-4 py-3 text-center text-sm font-semibold text-white">
              Создать поиск
            </Link>
          </div>
        </Panel>
        {matches.length === 0 ? (
          <Panel className="text-center">
            <div className="text-xl font-bold text-ink">Пока нет мэтчей</div>
            <div className="mt-2 text-sm leading-6 text-ink/65">
              Начни с поиска и поставь несколько лайков. Взаимные лайки появятся здесь автоматически.
            </div>
            <Link href="/discover" className="mt-4 inline-block rounded-2xl bg-ink px-4 py-3 text-sm font-semibold text-white">
              Открыть поиск
            </Link>
          </Panel>
        ) : null}

        {matches.map((match) => {
          const otherUser = match.user1Id === user.id ? match.user2 : match.user1;
          const latestRequest = match.gameRequests[0];

          return (
            <div key={match.id} className="space-y-3">
              <Link href={`/inbox/${match.id}`}>
                <Panel className="flex items-center gap-3">
                  <Avatar src={otherUser.avatarUrl} alt={otherUser.name ?? "Player"} />
                  <div className="min-w-0 flex-1">
                    <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Игрок</div>
                    <div className="mt-1 truncate text-xl font-bold text-ink">{otherUser.name}</div>
                    <div className="mt-1 text-xs font-medium text-ink/55">{formatPresence(otherUser.lastActiveAt)}</div>
                    <div className="truncate text-sm text-ink/60">
                      {match.messages[0]?.text ?? "Сообщений пока нет. Предложи игру."}
                    </div>
                  </div>
                </Panel>
              </Link>
              {latestRequest ? (
                <GameRequestCard
                  gameRequest={{
                    ...latestRequest,
                    proposedDatetime: latestRequest.proposedDatetime.toISOString(),
                    durationMinutes: latestRequest.durationMinutes,
                    outcome: latestRequest.outcome,
                    outcomeUpdatedAt: latestRequest.outcomeUpdatedAt?.toISOString() ?? null
                  }}
                  currentUserId={user.id}
                  detailsHref={`/play/games/${latestRequest.id}`}
                />
              ) : null}
            </div>
          );
        })}
      </div>
    </PageShell>
  );
}

function formatPresence(lastActiveAt?: Date | null) {
  if (!lastActiveAt) {
    return "Редко заходит";
  }

  const diffMinutes = Math.max(0, Math.round((Date.now() - lastActiveAt.getTime()) / 60000));

  if (diffMinutes <= 5) {
    return "Сейчас онлайн";
  }

  if (diffMinutes < 60) {
    return `Был ${diffMinutes} мин назад`;
  }

  const diffHours = Math.round(diffMinutes / 60);
  if (diffHours < 24) {
    return `Был ${diffHours} ч назад`;
  }

  return `Был ${lastActiveAt.toLocaleDateString("ru-RU")}`;
}
