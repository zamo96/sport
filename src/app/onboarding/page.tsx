import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { ProfileForm } from "@/components/forms/profile-form";
import { PageShell } from "@/components/layout/page-shell";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";

export default async function OnboardingPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  if (user.onboardingCompleted) {
    redirect("/discover");
  }

  return (
    <PageShell withNav={false}>
      <SectionTitle
        eyebrow="Онбординг"
        title="Заполни профиль за 1 минуту"
        subtitle="Тут всего 3 шага. Обязательное — базовые данные и хотя бы один спорт с уровнем. Доступность можно указать позже."
      />
      <Panel className="space-y-3 bg-cream text-sm leading-6 text-ink/70">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">Обязательно</div>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            <li>Шаг 1: имя и возраст (18+)</li>
            <li>Шаг 2: минимум 1 вид спорта и уровень</li>
          </ul>
        </div>
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">Можно позже</div>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            <li>дни и время, когда удобно играть</li>
            <li>районы и дополнительные детали профиля</li>
          </ul>
        </div>
      </Panel>
      <ProfileForm user={user} mode="onboarding" />
    </PageShell>
  );
}
