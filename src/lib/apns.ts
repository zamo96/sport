import { connect as http2Connect, constants as http2Constants } from "http2";
import { createPrivateKey, createSign } from "crypto";

import { prisma } from "@/lib/prisma";

type PushEnvironment = "development" | "production";

type PushPayload = {
  userId: string;
  title: string;
  body: string;
  href: string;
  sound?: boolean;
};

type APNSConfig = {
  teamId: string;
  keyId: string;
  privateKey: string;
};

let cachedAuthToken: { value: string; expiresAt: number } | null = null;

function getAPNSConfig(): APNSConfig | null {
  const teamId = process.env.APNS_TEAM_ID?.trim();
  const keyId = process.env.APNS_KEY_ID?.trim();
  const rawPrivateKey = process.env.APNS_PRIVATE_KEY?.trim();

  if (!teamId || !keyId || !rawPrivateKey) {
    return null;
  }

  const privateKey = rawPrivateKey.includes("BEGIN PRIVATE KEY")
    ? rawPrivateKey.replace(/\\n/g, "\n")
    : Buffer.from(rawPrivateKey, "base64").toString("utf8");

  return {
    teamId,
    keyId,
    privateKey
  };
}

function toBase64URL(input: Buffer | string) {
  const buffer = Buffer.isBuffer(input) ? input : Buffer.from(input);
  return buffer
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function derToJose(signature: Buffer, expectedPartLength: number) {
  let offset = 0;

  if (signature[offset++] !== 0x30) {
    throw new Error("Некорректная DER-подпись APNs JWT");
  }

  const sequenceLength = signature[offset++];
  if (sequenceLength & 0x80) {
    offset += sequenceLength & 0x7f;
  }

  if (signature[offset++] !== 0x02) {
    throw new Error("Некорректный DER формат r");
  }

  const rLength = signature[offset++];
  const r = signature.subarray(offset, offset + rLength);
  offset += rLength;

  if (signature[offset++] !== 0x02) {
    throw new Error("Некорректный DER формат s");
  }

  const sLength = signature[offset++];
  const s = signature.subarray(offset, offset + sLength);

  const jose = Buffer.alloc(expectedPartLength * 2);
  const normalizedR = r[0] === 0 ? r.subarray(1) : r;
  const normalizedS = s[0] === 0 ? s.subarray(1) : s;

  normalizedR.copy(jose, expectedPartLength - normalizedR.length);
  normalizedS.copy(jose, expectedPartLength * 2 - normalizedS.length);

  return jose;
}

function getAPNSAuthToken() {
  const config = getAPNSConfig();
  if (!config) {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  if (cachedAuthToken && cachedAuthToken.expiresAt > now + 60) {
    return cachedAuthToken.value;
  }

  const header = toBase64URL(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const payload = toBase64URL(JSON.stringify({ iss: config.teamId, iat: now }));
  const signingInput = `${header}.${payload}`;

  const signer = createSign("SHA256");
  signer.update(signingInput);
  signer.end();

  const derSignature = signer.sign(createPrivateKey(config.privateKey));
  const joseSignature = toBase64URL(derToJose(derSignature, 32));
  const token = `${signingInput}.${joseSignature}`;

  cachedAuthToken = {
    value: token,
    expiresAt: now + 50 * 60
  };

  return token;
}

function getAPNSHost(environment: PushEnvironment) {
  return environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
}

export async function sendPushToUser(payload: PushPayload) {
  const devices = await prisma.pushDevice.findMany({
    where: {
      userId: payload.userId,
      platform: "ios",
      isActive: true
    },
    select: {
      id: true,
      token: true,
      bundleId: true,
      environment: true
    }
  });

  if (devices.length === 0) {
    return;
  }

  await Promise.all(
    devices.map(async (device) => {
      try {
        const response = await new Promise<{ status: number; body: string }>((resolve, reject) => {
          const authToken = getAPNSAuthToken();
          if (!authToken) {
            reject(new Error("APNs не настроен: отсутствуют TEAM_ID / KEY_ID / PRIVATE_KEY"));
            return;
          }

          const client = http2Connect(getAPNSHost(device.environment));
          client.on("error", reject);

          const request = client.request({
            [http2Constants.HTTP2_HEADER_SCHEME]: "https",
            [http2Constants.HTTP2_HEADER_METHOD]: "POST",
            [http2Constants.HTTP2_HEADER_PATH]: `/3/device/${device.token}`,
            authorization: `bearer ${authToken}`,
            "apns-topic": device.bundleId,
            "apns-push-type": "alert",
            "apns-priority": "10"
          });

          const apnsPayload = JSON.stringify({
            aps: {
              alert: {
                title: payload.title,
                body: payload.body
              },
              sound: payload.sound === false ? undefined : "default"
            },
            href: payload.href
          });

          let responseBody = "";
          let responseStatus = 500;

          request.setEncoding("utf8");
          request.on("response", (headers) => {
            responseStatus = Number(headers[http2Constants.HTTP2_HEADER_STATUS] ?? 500);
          });
          request.on("data", (chunk) => {
            responseBody += chunk;
          });
          request.on("error", (error) => {
            client.close();
            reject(error);
          });
          request.on("end", () => {
            client.close();
            resolve({ status: responseStatus, body: responseBody });
          });

          request.end(apnsPayload);
        });

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

        const reason = response.body || `APNs HTTP ${response.status}`;
        const shouldDeactivate = response.status === 410 || reason.includes("BadDeviceToken") || reason.includes("Unregistered");

        await prisma.pushDevice.update({
          where: { id: device.id },
          data: {
            isActive: shouldDeactivate ? false : true,
            lastFailureAt: new Date(),
            lastFailureReason: reason
          }
        });
      } catch (error) {
        await prisma.pushDevice.update({
          where: { id: device.id },
          data: {
            lastFailureAt: new Date(),
            lastFailureReason: error instanceof Error ? error.message : "APNs request failed"
          }
        });
      }
    })
  );
}
