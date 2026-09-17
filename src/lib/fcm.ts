import { createSign } from "crypto";

import { prisma } from "@/lib/prisma";
import type { PushPayload } from "@/lib/push-payload";

type FCMConfig = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

type FCMDeviceTarget = {
  id: string;
  token: string;
};

const OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function getFCMConfig(): FCMConfig | null {
  const projectId = process.env.FCM_PROJECT_ID?.trim();
  const clientEmail = process.env.FCM_CLIENT_EMAIL?.trim();
  const rawPrivateKey = process.env.FCM_PRIVATE_KEY?.trim();

  if (!projectId || !clientEmail || !rawPrivateKey) {
    return null;
  }

  // The service-account key is a PEM whose newlines survive an env var badly,
  // so it is accepted either escaped or base64-encoded, like the APNs one.
  const privateKey = rawPrivateKey.includes("BEGIN PRIVATE KEY")
    ? rawPrivateKey.replace(/\\n/g, "\n")
    : Buffer.from(rawPrivateKey, "base64").toString("utf8");

  return { projectId, clientEmail, privateKey };
}

function toBase64URL(input: Buffer | string) {
  const buffer = Buffer.isBuffer(input) ? input : Buffer.from(input);
  return buffer
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

/** Signs the service-account assertion Google exchanges for an access token. */
function buildServiceAccountAssertion(config: FCMConfig) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = toBase64URL(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = toBase64URL(
    JSON.stringify({
      iss: config.clientEmail,
      scope: FCM_SCOPE,
      aud: OAUTH_TOKEN_URL,
      iat: issuedAt,
      exp: issuedAt + 3600
    })
  );

  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${claims}`);
  signer.end();

  return `${header}.${claims}.${toBase64URL(signer.sign(config.privateKey))}`;
}

async function getFCMAccessToken(config: FCMConfig) {
  const now = Date.now();
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60_000) {
    return cachedAccessToken.value;
  }

  const response = await fetch(OAUTH_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: buildServiceAccountAssertion(config)
    })
  });

  const payload = (await response.json().catch(() => null)) as
    | { access_token?: string; expires_in?: number; error_description?: string }
    | null;

  if (!response.ok || !payload?.access_token) {
    throw new Error(payload?.error_description ?? `FCM OAuth HTTP ${response.status}`);
  }

  cachedAccessToken = {
    value: payload.access_token,
    expiresAt: now + (payload.expires_in ?? 3600) * 1000
  };

  return cachedAccessToken.value;
}

/** Exported for tests: a new process should not reuse another one's token. */
export function resetFCMAccessTokenCache() {
  cachedAccessToken = null;
}

function parseFCMFailureReason(body: string, fallback: string) {
  try {
    const parsed = JSON.parse(body) as {
      error?: { status?: string; message?: string; details?: { errorCode?: string }[] };
    };
    return (
      parsed.error?.details?.find((detail) => detail.errorCode)?.errorCode ??
      parsed.error?.status ??
      parsed.error?.message ??
      fallback
    );
  } catch {
    return fallback;
  }
}

/**
 * A token that Google says is gone stays gone - reinstalling the app mints a
 * new one - so the row is retired instead of being retried forever.
 */
function shouldDeactivateFCMDevice(status: number, reason: string) {
  if (status === 404) return true;
  if (status === 403) return false;
  return reason === "UNREGISTERED" || reason === "INVALID_ARGUMENT" || reason === "NOT_FOUND";
}

async function deliverFCMToDevice(
  config: FCMConfig,
  accessToken: string,
  device: FCMDeviceTarget,
  payload: PushPayload
) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${config.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        message: {
          token: device.token,
          notification: { title: payload.title, body: payload.body },
          // The app reads these to route the tap the same way the APNs payload does.
          data: {
            href: payload.href,
            ...(payload.deliveryId ? { deliveryId: payload.deliveryId } : {})
          },
          android: {
            priority: "high",
            notification: {
              default_sound: payload.sound !== false,
              click_action: "shop.sportsearch.app.OPEN_HREF"
            }
          }
        }
      })
    }
  );

  return { status: response.status, body: await response.text() };
}

/**
 * Delivers one notification to a user's Android devices. Mirrors
 * `deliverAPNSPush`: it never throws, it records why a device failed, and it
 * retires tokens Google has dropped.
 */
export async function deliverFCMPush(payload: PushPayload) {
  const config = getFCMConfig();

  const devices = await prisma.pushDevice.findMany({
    where: {
      userId: payload.userId,
      platform: "android",
      isActive: true
    },
    select: { id: true, token: true }
  });

  if (devices.length === 0) {
    return;
  }

  if (!config) {
    console.warn("FCM push skipped: FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY are not set", {
      userId: payload.userId,
      href: payload.href
    });
    return;
  }

  let accessToken: string;
  try {
    accessToken = await getFCMAccessToken(config);
  } catch (error) {
    console.error("FCM push failed: could not mint an access token", {
      userId: payload.userId,
      error: error instanceof Error ? error.message : "FCM OAuth failed"
    });
    return;
  }

  await Promise.all(
    devices.map(async (device) => {
      try {
        const response = await deliverFCMToDevice(config, accessToken, device, payload);

        if (response.status >= 200 && response.status < 300) {
          await prisma.pushDevice.update({
            where: { id: device.id },
            data: {
              lastDeliveredAt: new Date(),
              lastFailureAt: null,
              lastFailureReason: null
            }
          });
          return;
        }

        const reason = parseFCMFailureReason(response.body, `FCM HTTP ${response.status}`);

        console.error("FCM push failed", {
          userId: payload.userId,
          deviceId: device.id,
          status: response.status,
          reason
        });

        await prisma.pushDevice.update({
          where: { id: device.id },
          data: {
            isActive: !shouldDeactivateFCMDevice(response.status, reason),
            lastFailureAt: new Date(),
            lastFailureReason: reason
          }
        });
      } catch (error) {
        console.error("FCM push request error", {
          userId: payload.userId,
          deviceId: device.id,
          error: error instanceof Error ? error.message : "FCM request failed"
        });

        await prisma.pushDevice.update({
          where: { id: device.id },
          data: {
            lastFailureAt: new Date(),
            lastFailureReason: error instanceof Error ? error.message : "FCM request failed"
          }
        });
      }
    })
  );
}
