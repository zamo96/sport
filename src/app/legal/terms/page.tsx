import Link from "next/link";
import type { Metadata } from "next";

import {
  getUserAgreementDocument,
  LEGAL_OPERATOR,
  resolveLegalLanguage
} from "@/lib/legal";
import { PageShell } from "@/components/layout/page-shell";

type TermsPageProps = {
  searchParams?: {
    lang?: string | string[];
  };
};

export function generateMetadata({ searchParams }: TermsPageProps): Metadata {
  const document = getUserAgreementDocument(searchParams?.lang);

  return {
    title: document.title,
    description: document.description
  };
}

const LANGUAGE_OPTIONS = [
  { value: "ru", label: "Русский" },
  { value: "en", label: "English" }
] as const;

export default function TermsPage({ searchParams }: TermsPageProps) {
  const language = resolveLegalLanguage(searchParams?.lang);
  const document = getUserAgreementDocument(language);

  return (
    <PageShell withNav={false}>
      <article lang={document.language} className="space-y-4 pb-10">
        <header className="rounded-[28px] border border-white/70 bg-white/82 p-5 shadow-card">
          <Link href="/auth" className="text-sm font-semibold text-court">
            {document.backLabel}
          </Link>

          <nav
            aria-label={language === "en" ? "Agreement language" : "Язык соглашения"}
            className="mt-4 inline-flex rounded-full border border-ink/10 bg-white/70 p-1"
          >
            {LANGUAGE_OPTIONS.map((option) => {
              const isActive = option.value === language;

              return (
                <Link
                  key={option.value}
                  href={`/legal/terms?lang=${option.value}`}
                  hrefLang={option.value}
                  lang={option.value}
                  aria-current={isActive ? "page" : undefined}
                  className={`inline-flex min-h-11 items-center justify-center rounded-full px-4 py-2 text-sm font-semibold transition-colors ${
                    isActive ? "bg-court text-white" : "text-ink/68 hover:bg-court/10 hover:text-court"
                  }`}
                >
                  {option.label}
                </Link>
              );
            })}
          </nav>

          <h1 className="mt-3 text-2xl font-bold leading-tight text-ink">{document.title}</h1>
          <div className="mt-3 space-y-1 text-sm leading-6 text-ink/68">
            <p>{document.versionLabel}: {document.version}</p>
            <p>{document.effectiveDateLabel}: {document.effectiveDate}</p>
            <p>{document.operatorLabel}: {LEGAL_OPERATOR.legalName}</p>
          </div>
        </header>

        <div className="space-y-3">
          {document.sections.map((section) => (
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
