import { NextRequest, NextResponse } from "next/server";

/** Префиксы state, с которыми вход начинают приложения: код нужно вернуть им. */
const APP_STATE_PREFIXES = ["ios_", "android_"];

/**
 * Сюда VK ID возвращает пользователя. Вход из приложения — код, device_id и
 * state уходят в приложение по схеме sportsearch:// (code_verifier есть только
 * там). Перенаправление серверное: переход по своей схеме из скрипта Chrome на
 * Android может заблокировать, а в цепочке HTTP-редиректов — нет.
 * Вход из браузера завершает страница /auth/vk/finish.
 */
export function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const state = params.get("state") ?? "";
  const target = APP_STATE_PREFIXES.some((prefix) => state.startsWith(prefix))
    ? new URL("sportsearch://auth/vk")
    : new URL("/auth/vk/finish", request.nextUrl.origin);
  params.forEach((value, key) => target.searchParams.set(key, value));
  return NextResponse.redirect(target, 302);
}
