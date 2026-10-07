import { appLatestVersion, appMinSupportedVersion } from "@/lib/app-version";
import { ok } from "@/lib/http";

export const dynamic = "force-dynamic";

export async function GET() {
  return ok({
    latestVersion: appLatestVersion(),
    minVersion: appMinSupportedVersion()
  });
}
