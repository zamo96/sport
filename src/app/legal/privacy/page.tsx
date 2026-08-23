import Link from "next/link";
import type { Metadata } from "next";

import {
  LEGAL_OPERATOR,
  PRIVACY_POLICY_EFFECTIVE_DATE,
  PRIVACY_POLICY_SECTIONS,
  PRIVACY_POLICY_TITLE,
  PRIVACY_POLICY_VERSION
} from "@/lib/legal";
import { PageShell } from "@/components/layout/page-shell";

export const metadata: Metadata = {
  title: PRIVACY_POLICY_TITLE,
  description: "Политика конфиденциальности приложения SportSearch"
};

export default function PrivacyPolicyPage() {
  return (
    <PageShell withNav={false}>
      <article className="space-y-4 pb-10">
        <header className="rounded-[28px] border border-white/70 bg-white/82 p-5 shadow-card">
          <Link href="/support" className="text-sm font-semibold text-court">
            Поддержка SportSearch
          </Link>
          <h1 className="mt-3 text-2xl font-bold leading-tight text-ink">{PRIVACY_POLICY_TITLE}</h1>
          <div className="mt-3 space-y-1 text-sm leading-6 text-ink/68">
            <p>Редакция: {PRIVACY_POLICY_VERSION}</p>
            <p>Дата вступления в силу: {PRIVACY_POLICY_EFFECTIVE_DATE}</p>
            <p>Оператор: {LEGAL_OPERATOR.legalName}</p>
          </div>
        </header>

        <div className="space-y-3">
          {PRIVACY_POLICY_SECTIONS.map((section) => (
            <section key={section.title} className="rounded-[24px] border border-white/70 bg-white/82 p-4 shadow-card">
              <h2 className="text-lg font-bold leading-snug text-ink">{section.title}</h2>
              {section.paragraphs?.map((paragraph) => (
                <p key={paragraph} className="mt-3 text-sm leading-6 text-ink/72">
                  {paragraph}
                </p>
              ))}
              {section.bullets ? (
                <ul className="mt-3 list-disc space-y-2 pl-5 text-sm leading-6 text-ink/72">
                  {section.bullets.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              ) : null}
            </section>
          ))}
        </div>
      </article>
    </PageShell>
  );
}
