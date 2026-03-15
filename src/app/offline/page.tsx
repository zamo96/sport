import Link from "next/link";

import { PageShell } from "@/components/layout/page-shell";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";

export default function OfflinePage() {
  return (
    <PageShell withNav={false}>
      <SectionTitle
        eyebrow="Офлайн"
        title="Сейчас приложение работает в офлайн-режиме."
        subtitle="Оболочка PWA доступна, но для поиска, чатов и договоренностей нужен интернет."
      />
      <Panel className="space-y-4">
        <div className="text-sm leading-6 text-ink/68">
          Подключись к сети, чтобы продолжить свайпать, обновлять чаты и отправлять предложения.
        </div>
        <Link href="/discover">
          <Button>Повторить</Button>
        </Link>
      </Panel>
    </PageShell>
  );
}
