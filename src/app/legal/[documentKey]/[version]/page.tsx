import { notFound } from "next/navigation";
import { LegalDocumentPage } from "@/components/legal/legal-document-page";
import { resolveLegalLanguage } from "@/lib/legal";
import { getLegalDocumentRegistryEntry, type LegalDocumentKey } from "@/server/legal-documents";

type Props = { params: { documentKey: string; version: string }; searchParams?: { lang?: string | string[]; hash?: string | string[] } };
const KEYS: LegalDocumentKey[] = ["terms", "privacy", "profile-visibility", "analytics", "recommendations"];

export default function ImmutableLegalPage({ params, searchParams }: Props) {
  if (!KEYS.includes(params.documentKey as LegalDocumentKey)) notFound();
  let document;
  try { document = getLegalDocumentRegistryEntry(params.documentKey as LegalDocumentKey, resolveLegalLanguage(searchParams?.lang), params.version); }
  catch { notFound(); }
  if (searchParams?.hash && searchParams.hash !== document.hash) notFound();
  return <LegalDocumentPage document={document} />;
}
