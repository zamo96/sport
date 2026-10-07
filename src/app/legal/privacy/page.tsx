import type { Metadata } from "next";
import { LegalDocumentPage } from "@/components/legal/legal-document-page";
import { resolveLegalLanguage } from "@/lib/legal";
import { getLegalDocumentRegistryEntry } from "@/server/legal-documents";

type Props = { searchParams?: { lang?: string | string[] } };

export function generateMetadata({ searchParams }: Props): Metadata {
  const document = getLegalDocumentRegistryEntry("privacy", resolveLegalLanguage(searchParams?.lang));
  return { title: document.title, description: document.description };
}

/**
 * The current policy, rendered like its versioned receipt: the purposes, data, grounds
 * and terms are a table, which the old page left out.
 */
export default function PrivacyPolicyPage({ searchParams }: Props) {
  return <LegalDocumentPage document={getLegalDocumentRegistryEntry("privacy", resolveLegalLanguage(searchParams?.lang))} />;
}
