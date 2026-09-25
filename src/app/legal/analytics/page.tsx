import type { Metadata } from "next";

import { ConsentDocumentPage } from "@/components/legal/consent-document-page";
import { resolveLegalLanguage } from "@/lib/legal";
import { getConsentDocument } from "@/lib/legal-consents";

type PageProps = { searchParams?: { lang?: string | string[] } };

export function generateMetadata({ searchParams }: PageProps): Metadata {
  const document = getConsentDocument("analytics", resolveLegalLanguage(searchParams?.lang));
  return { title: document.title, description: document.description };
}

export default function AnalyticsConsentPage({ searchParams }: PageProps) {
  const document = getConsentDocument("analytics", resolveLegalLanguage(searchParams?.lang));
  return <ConsentDocumentPage documentKey="analytics" document={document} />;
}
