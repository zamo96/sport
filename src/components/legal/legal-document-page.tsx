import Link from "next/link";
import { PageShell } from "@/components/layout/page-shell";
import { getLegalDocumentRegistryEntry, type LegalDocumentKey } from "@/server/legal-documents";

type Entry = ReturnType<typeof getLegalDocumentRegistryEntry>;

/** Renders the same complete body used by the server's immutable consent receipt. */
export function LegalDocumentPage({ document }: { document: Entry }) {
  const english = document.language === "en";
  return (
    <PageShell withNav={false}>
      <article lang={document.language} className="space-y-4 pb-10">
        <header className="rounded-[28px] border border-white/70 bg-white/82 p-5 shadow-card">
          <Link href="/support" className="text-sm font-semibold text-court">{english ? "Support" : "Поддержка"}</Link>
          <nav aria-label={english ? "Document language" : "Язык документа"} className="mt-4 flex gap-3">
            {(["ru", "en"] as const).map((language) => {
              let alternative: Entry;
              try { alternative = getLegalDocumentRegistryEntry(document.key as LegalDocumentKey, language, document.version); }
              catch { return null; }
              return <Link key={language} href={alternative.url} hrefLang={language} lang={language} aria-current={language === document.language ? "page" : undefined} className="text-sm font-semibold text-court underline">{language === "ru" ? "Русский" : "English"}</Link>;
            })}
          </nav>
          <h1 className="mt-3 text-2xl font-bold leading-tight text-ink">{document.title}</h1>
          <div className="mt-3 space-y-1 text-sm leading-6 text-ink/68">
            {document.description ? <p className="whitespace-pre-line">{document.description}</p> : null}
            <p>{english ? "Revision" : "Редакция"}: {document.version}</p>
            {document.effectiveDate ? <p>{english ? "Revision date" : "Дата редакции"}: {document.effectiveDate}</p> : null}
            <p>{english ? "Operator" : "Оператор"}: {document.operator.legalName}</p>
          </div>
        </header>
        {document.sections.map((section) => (
          <section key={section.title} className="rounded-[24px] border border-white/70 bg-white/82 p-4 shadow-card">
            <h2 className="text-lg font-bold leading-snug text-ink">{section.title}</h2>
            {section.paragraphs?.map((paragraph) => <p key={paragraph} className="mt-3 text-sm leading-6 text-ink/72">{paragraph}</p>)}
            {section.bullets ? <ul className="mt-3 list-disc space-y-2 pl-5 text-sm leading-6 text-ink/72">{section.bullets.map((item) => <li key={item}>{item}</li>)}</ul> : null}
            {section.table ? <div className="mt-4 overflow-x-auto"><table className="min-w-[720px] text-left text-sm leading-6 text-ink/72"><thead><tr>{section.table.headers.map((header) => <th key={header} scope="col" className="border border-line p-3 align-top font-semibold">{header}</th>)}</tr></thead><tbody>{section.table.rows.map((row, index) => <tr key={index}>{row.map((cell, column) => <td key={column} className="border border-line p-3 align-top">{cell}</td>)}</tr>)}</tbody></table></div> : null}
          </section>
        ))}
      </article>
    </PageShell>
  );
}
