import type { Metadata } from "next";
import { LegalDocumentPage } from "@/components/legal/legal-document-page";
import { resolveLegalLanguage } from "@/lib/legal";
import { getLegalDocumentRegistryEntry } from "@/server/legal-documents";
type Props = { searchParams?: { lang?: string | string[] } };
export function generateMetadata({ searchParams }: Props): Metadata {
  const document = getLegalDocumentRegistryEntry("recommendations", resolveLegalLanguage(searchParams?.lang));
  return { title: document.title, description: document.description };
}
export default function Page({ searchParams }: Props) {
  return <LegalDocumentPage document={getLegalDocumentRegistryEntry("recommendations", resolveLegalLanguage(searchParams?.lang))} />;
}
