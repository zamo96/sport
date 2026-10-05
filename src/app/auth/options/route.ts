import { ok } from "@/lib/http";
import { isSmsSignInEnabled } from "@/server/sms";
import { vkIdConfig } from "@/server/vk-auth";

export const dynamic = "force-dynamic";

/** Which sign-in methods the clients should show: SMS and VK ID depend on server settings. */
export async function GET() {
  const vk = vkIdConfig();
  return ok({
    sms: isSmsSignInEnabled(),
    vk: {
      available: vk.available,
      clientId: vk.clientId,
      redirectUri: vk.redirectUri,
      scope: vk.scope,
      authorizeUrl: vk.authorizeUrl
    }
  });
}
