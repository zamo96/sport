import { APP_LATEST_VERSION, APP_MIN_SUPPORTED_VERSION } from "@/lib/app-version";
import { ok } from "@/lib/http";

export const dynamic = "force-dynamic";

export async function GET() {
  return ok({
    latestVersion: APP_LATEST_VERSION,
    minVersion: APP_MIN_SUPPORTED_VERSION
  });
}
