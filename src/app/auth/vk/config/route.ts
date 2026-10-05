import { ok } from "@/lib/http";
import { vkIdConfig } from "@/server/vk-auth";

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
