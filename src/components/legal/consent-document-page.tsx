import { LegalDocumentPage } from "@/components/legal/legal-document-page";
import { getLegalDocumentRegistryEntry } from "@/server/legal-documents";
import type { ConsentDocument, ConsentDocumentKey } from "@/lib/legal-consents";
export function ConsentDocumentPage({ documentKey, document }: { documentKey: ConsentDocumentKey; document: ConsentDocument }) {
  return <LegalDocumentPage document={getLegalDocumentRegistryEntry(documentKey, document.language, document.version)} />;
}
