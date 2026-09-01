import { createAppleAppSiteAssociationResponse } from "@/lib/deep-links";

export const dynamic = "force-static";

export function GET() {
  return createAppleAppSiteAssociationResponse();
}
