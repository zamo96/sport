import Link from "next/link";
import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { PageShell } from "@/components/layout/page-shell";
import { LiveRefresh } from "@/components/ui/live-refresh";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";
import { NotificationsSeenMarker } from "@/components/notifications/notifications-seen-marker";
import { getNotificationsForUser } from "@/server/app-data";

export default async function NotificationsPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/notifications"));
  }

  const notifications = await getNotificationsForUser(user.id);
  const groupedNotifications = groupNotifications(notifications);

  return (
    <PageShell>
      <NotificationsSeenMarker />
      <LiveRefresh intervalMs={10000} />
      <SectionTitle
        eyebrow="Уведомления"
        title="Что требует внимания прямо сейчас."
        subtitle="Новые мэтчи, сообщения, входящие лайки, решения по откликам и срочные события."
      />

      <div className="mb-4 flex gap-3">
        <Link href="/settings" className="rounded-2xl bg-cream px-4 py-3 text-sm font-semibold text-ink">
          Настройки
        </Link>
        <Link href="/discover" className="rounded-2xl bg-ink px-4 py-3 text-sm font-semibold text-white">
          Открыть поиск
        </Link>
      </div>

      <div className="space-y-4">
        {notifications.length === 0 ? (
          <Panel className="text-center">
            <div className="text-xl font-bold text-ink">Пока всё спокойно</div>
            <div className="mt-2 text-sm leading-6 text-ink/65">
              Здесь будут входящие лайки, срочные события и изменения по твоим заявкам.
            </div>
          </Panel>
        ) : null}

        {groupedNotifications.map((group) => (
          <section key={group.type} className="space-y-3">
            <div className="flex items-center justify-between px-1">
              <div>
                <div className="text-lg font-bold text-ink">{translateNotificationType(group.type)}</div>
              </div>
              <div className="rounded-full bg-white/80 px-3 py-1.5 text-xs font-semibold text-ink/65">
                {group.items.length}
              </div>
            </div>

            {group.items.map((notification) => (
              <Link key={notification.id} href={notification.href} className="block">
                <Panel className="space-y-2">
                  <div className="flex items-center justify-between gap-3">
                    <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">
                      {translateNotificationType(notification.type)}
                    </div>
                    <div className="text-xs text-ink/45">
                      {notification.createdAt.toLocaleString("ru-RU", {
                        day: "2-digit",
                        month: "2-digit",
                        hour: "2-digit",
                        minute: "2-digit"
                      })}
                    </div>
                  </div>
                  <div className="text-lg font-bold text-ink">{notification.title}</div>
                  <div className="text-sm leading-6 text-ink/68">{notification.description}</div>
                </Panel>
              </Link>
            ))}
          </section>
        ))}
      </div>
    </PageShell>
  );
}

function groupNotifications<T extends { type: string; createdAt: Date }>(notifications: T[]) {
  const order = ["new_message", "new_match", "incoming_like", "search_response", "application_result", "hot_event"];
  const groups = new Map<string, T[]>();

  for (const notification of notifications) {
    if (!groups.has(notification.type)) {
      groups.set(notification.type, []);
    }

    groups.get(notification.type)?.push(notification);
  }

  return Array.from(groups.entries())
    .sort((left, right) => {
      const leftIndex = order.indexOf(left[0]);
      const rightIndex = order.indexOf(right[0]);

      if (leftIndex === -1 && rightIndex === -1) {
        return right[1][0].createdAt.getTime() - left[1][0].createdAt.getTime();
      }

      if (leftIndex === -1) return 1;
      if (rightIndex === -1) return -1;
      return leftIndex - rightIndex;
    })
    .map(([type, items]) => ({
      type,
      items
    }));
}

function translateNotificationType(type: string) {
  switch (type) {
    case "new_match":
      return "Новый мэтч";
    case "new_message":
      return "Новое сообщение";
    case "incoming_like":
      return "Хочет с тобой сыграть";
    case "search_response":
      return "Новый отклик";
    case "application_result":
      return "Решение по заявке";
    case "hot_event":
      return "Срочное событие";
    default:
      return "Уведомление";
  }
}
