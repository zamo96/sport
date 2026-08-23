import Link from "next/link";
import type { Metadata } from "next";
import { HelpCircle, Mail, ShieldCheck, Trash2 } from "lucide-react";

import { LEGAL_OPERATOR } from "@/lib/legal";
import { PageShell } from "@/components/layout/page-shell";

export const metadata: Metadata = {
  title: "Поддержка SportSearch",
  description: "Помощь, контакты поддержки и юридические ссылки приложения SportSearch"
};

const supportTopics = [
  {
    title: "Проблема со входом",
    text: "Укажите email аккаунта, способ входа и что происходит после запроса кода или входа через Apple.",
    icon: HelpCircle
  },
  {
    title: "Игры, чаты и уведомления",
    text: "Опишите экран, действие, время события и приложите скриншот, если он помогает понять проблему.",
    icon: Mail
  },
  {
    title: "Удаление аккаунта",
    text: "Напишите с email аккаунта и укажите, что хотите удалить аккаунт и связанные с ним персональные данные.",
    icon: Trash2
  }
];

export default function SupportPage() {
  return (
    <PageShell withNav={false}>
      <article className="space-y-4 pb-10">
        <header className="rounded-[28px] border border-white/70 bg-white/82 p-5 shadow-card">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-court">SportSearch</p>
          <h1 className="mt-3 text-2xl font-bold leading-tight text-ink">Поддержка приложения</h1>
          <p className="mt-3 text-sm leading-6 text-ink/72">
            Если что-то не работает, нужна помощь с аккаунтом или вы хотите удалить данные, напишите в поддержку.
          </p>
          <a
            href={`mailto:${LEGAL_OPERATOR.email}`}
            className="mt-5 flex min-h-14 items-center justify-center rounded-2xl bg-ink px-4 text-center text-sm font-bold text-white shadow-glow"
          >
            Написать на {LEGAL_OPERATOR.email}
          </a>
        </header>

        <section className="rounded-[24px] border border-white/70 bg-white/82 p-4 shadow-card">
          <h2 className="text-lg font-bold leading-snug text-ink">Что указать в обращении</h2>
          <ul className="mt-3 list-disc space-y-2 pl-5 text-sm leading-6 text-ink/72">
            <li>Email аккаунта или способ входа, который вы использовали.</li>
            <li>Модель устройства и версию iOS, если проблема связана с приложением.</li>
            <li>Короткое описание: что вы ожидали, что произошло и на каком экране.</li>
            <li>Скриншот ошибки, если его можно безопасно приложить.</li>
          </ul>
        </section>

        <div className="space-y-3">
          {supportTopics.map((topic) => {
            const Icon = topic.icon;

            return (
              <section key={topic.title} className="rounded-[24px] border border-white/70 bg-white/82 p-4 shadow-card">
                <div className="flex items-start gap-3">
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-mint text-court">
                    <Icon className="h-5 w-5" aria-hidden="true" />
                  </span>
                  <div>
                    <h2 className="text-base font-bold leading-snug text-ink">{topic.title}</h2>
                    <p className="mt-2 text-sm leading-6 text-ink/72">{topic.text}</p>
                  </div>
                </div>
              </section>
            );
          })}
        </div>

        <section className="rounded-[24px] border border-white/70 bg-white/82 p-4 shadow-card">
          <div className="flex items-start gap-3">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-mint text-court">
              <ShieldCheck className="h-5 w-5" aria-hidden="true" />
            </span>
            <div>
              <h2 className="text-base font-bold leading-snug text-ink">Юридическая информация</h2>
              <div className="mt-2 space-y-2 text-sm leading-6 text-ink/72">
                <p>
                  <Link href="/legal/privacy" className="font-semibold text-court">
                    Политика конфиденциальности
                  </Link>
                </p>
                <p>
                  <Link href="/legal/terms" className="font-semibold text-court">
                    Пользовательское соглашение
                  </Link>
                </p>
              </div>
            </div>
          </div>
        </section>
      </article>
    </PageShell>
  );
}
