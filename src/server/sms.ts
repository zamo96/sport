import { getRealtimeRedis } from "@/server/realtime";

const SMS_RU_SEND_URL = "https://sms.ru/sms/send";
const DEFAULT_DAILY_LIMIT = 500;

export class SmsUnavailableError extends Error {}

type SmsRuResponse = {
  status?: string;
  status_code?: number;
  status_text?: string;
  sms?: Record<string, { status?: string; status_code?: number; status_text?: string; sms_id?: string }>;
};

function smsConfig() {
  const apiId = process.env.SMSRU_API_ID?.trim();
  return {
    apiId: apiId || null,
    from: process.env.SMSRU_FROM?.trim() || null,
    // SMS.ru test=1: ответ как при отправке, но SMS не уходит и баланс не списывается.
    test: ["1", "true"].includes(process.env.SMSRU_TEST?.trim() ?? ""),
    dailyLimit: Number(process.env.SMS_DAILY_LIMIT) > 0 ? Number(process.env.SMS_DAILY_LIMIT) : DEFAULT_DAILY_LIMIT
  };
}

/** Без ключа SMS.ru вне production код возвращается в ответе API, как debugCode у email. */
export function isSmsDevFallback() {
  return !smsConfig().apiId && process.env.NODE_ENV !== "production";
}

/**
 * Общий дневной потолок SMS на весь сервис: даже если накрутка обойдёт лимиты
 * на номер и IP, она не съест баланс SMS.ru целиком.
 */
async function reserveDailySms(limit: number) {
  const redis = getRealtimeRedis();
  if (!redis) return;
  const key = `tennis:sms:day:${new Date().toISOString().slice(0, 10)}`;
  try {
    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, 2 * 24 * 60 * 60);
    if (count > limit) throw new SmsUnavailableError("SMS_DAILY_LIMIT");
  } catch (error) {
    if (error instanceof SmsUnavailableError) throw error;
    // Лимит — страховка от расходов; недоступный Redis не должен ломать вход.
  }
}

export async function sendSms(phone: string, text: string, meta: { ip?: string | null } = {}) {
  const config = smsConfig();
  if (!config.apiId) {
    if (process.env.NODE_ENV === "production") throw new SmsUnavailableError("SMS_NOT_CONFIGURED");
    console.info(`[sms:dev] ${phone}: ${text}`);
    return { delivered: false, dev: true };
  }

  await reserveDailySms(config.dailyLimit);

  const body = new URLSearchParams({
    api_id: config.apiId,
    to: phone.replace(/^\+/, ""),
    msg: text,
    json: "1"
  });
  if (config.from) body.set("from", config.from);
  if (config.test) body.set("test", "1");
  if (meta.ip) body.set("ip", meta.ip);

  let payload: SmsRuResponse;
  try {
    const response = await fetch(SMS_RU_SEND_URL, { method: "POST", body, cache: "no-store" });
    payload = (await response.json()) as SmsRuResponse;
  } catch (error) {
    console.error("[sms] SMS.ru request failed", error);
    throw new SmsUnavailableError("SMS_PROVIDER_UNREACHABLE");
  }

  const perNumber = payload.sms ? Object.values(payload.sms)[0] : undefined;
  if (payload.status !== "OK" || perNumber?.status !== "OK") {
    console.error("[sms] SMS.ru rejected the message", {
      status: payload.status_code,
      text: payload.status_text,
      number: perNumber?.status_code,
      numberText: perNumber?.status_text
    });
    throw new SmsUnavailableError("SMS_PROVIDER_REJECTED");
  }
  return { delivered: !config.test, dev: false };
}
