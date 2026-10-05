import { ok } from "@/lib/http";
import { vkIdConfig } from "@/server/vk-auth";

// VK_ID_CLIENT_ID lives in the runtime env, not in the image: a page rendered at
// build time would report VK ID as unavailable forever.
export const dynamic = "force-dynamic";

/** Параметры для ссылки на VK ID: клиенты не хранят client_id у себя. */
export async function GET() {
  const config = vkIdConfig();
  return ok({
    available: config.available,
    clientId: config.clientId,
    redirectUri: config.redirectUri,
    scope: config.scope,
    authorizeUrl: config.authorizeUrl
  });
}
