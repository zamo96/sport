import Link from "next/link";
import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { LiveRefresh } from "@/components/ui/live-refresh";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";
import { getNotificationsForUser } from "@/server/app-data";

export default async function NotificationsPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  const notifications = await getNotificationsForUser(user.id);

  return (
    <PageShell>
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

      <div className="space-y-3">
        {notifications.length === 0 ? (
          <Panel className="text-center">
            <div className="text-xl font-bold text-ink">Пока всё спокойно</div>
            <div className="mt-2 text-sm leading-6 text-ink/65">
              Здесь будут входящие лайки, срочные события и изменения по твоим заявкам.
            </div>
          </Panel>
        ) : null}

        {notifications.map((notification) => (
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
      </div>
    </PageShell>
  );
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
