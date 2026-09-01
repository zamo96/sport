import type { Metadata } from "next";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { Download, ShieldCheck } from "lucide-react";

import { PageShell } from "@/components/layout/page-shell";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";
import { APP_STORE_URL, shouldRedirectDeepLinkToAppStore } from "@/lib/deep-links";

export const metadata: Metadata = {
  title: "Профиль игрока · SportSearch",
  description: "Откройте профиль игрока в приложении SportSearch.",
  robots: {
    index: false,
    follow: false
  }
};

export default function SharedUserPage({ params }: { params: { id: string } }) {
  const pathname = `/users/${encodeURIComponent(params.id)}`;

  if (
    shouldRedirectDeepLinkToAppStore({
      pathname,
      userAgent: headers().get("user-agent")
    })
  ) {
    redirect(APP_STORE_URL);
  }

  return (
    <PageShell withNav={false}>
      <div className="flex min-h-[calc(100vh-2rem)] items-center">
        <div className="w-full">
          <SectionTitle
            eyebrow="SportSearch"
            title="Профиль доступен в приложении"
            subtitle="Установите SportSearch на iPhone или iPad, чтобы безопасно открыть профиль игрока."
          />

          <Panel className="space-y-5">
            <div className="flex items-start gap-3 rounded-2xl bg-mint px-4 py-4 text-sm leading-6 text-ink/75">
              <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-court" aria-hidden="true" />
              <p className="m-0">
                Мы не показываем данные профиля на публичной веб-странице. После установки откройте исходную ссылку ещё раз.
              </p>
            </div>

            <a
              href={APP_STORE_URL}
              className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl bg-ink px-4 text-sm font-semibold text-white shadow-card transition active:translate-y-px active:scale-[0.985]"
            >
              <Download className="h-4 w-4" aria-hidden="true" />
              Скачать в App Store
            </a>
          </Panel>
        </div>
      </div>
    </PageShell>
  );
}
