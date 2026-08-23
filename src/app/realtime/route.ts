import { NextRequest } from "next/server";
import type Redis from "ioredis";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { getRealtimeRedis, getRealtimeStreamKey } from "@/server/realtime";
import { touchUserActivity } from "@/server/user-activity";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const encoder = new TextEncoder();
const READ_BLOCK_MS = 25_000;
const HEARTBEAT_MS = 15_000;

type RedisStreamReadResult = Array<[string, Array<[string, string[]]>]> | null;

export async function GET(request: NextRequest) {
  let redis: Redis | null = null;

  try {
    const user = await requireSessionUser();
    await touchUserActivity(user.id);

    const baseRedis = getRealtimeRedis();
    if (!baseRedis) {
      return fail("Realtime Redis не настроен", 503);
    }

    redis = baseRedis.duplicate();
    const streamKey = getRealtimeStreamKey(user.id);
    const initialCursor =
      request.headers.get("last-event-id")?.trim() ||
      request.nextUrl.searchParams.get("cursor")?.trim() ||
      "$";

    let cursor = normalizeCursor(initialCursor);
    let isClosed = false;
    let lastAccountCheckAt = Date.now();

    const stream = new ReadableStream<Uint8Array>({
      async start(controller) {
        const heartbeat = setInterval(() => {
          safeEnqueue(controller, ": heartbeat\n\n");
        }, HEARTBEAT_MS);

        safeEnqueue(controller, "retry: 2000\n\n");

        try {
          while (!isClosed) {
            const result = (await redis!.call(
              "XREAD",
              "BLOCK",
              READ_BLOCK_MS,
              "COUNT",
              25,
              "STREAMS",
              streamKey,
              cursor
            )) as RedisStreamReadResult;

            if (Date.now() - lastAccountCheckAt >= HEARTBEAT_MS) {
              lastAccountCheckAt = Date.now();
              const activeAccount = await prisma.user.findFirst({
                where: { id: user.id, accountStatus: "active" },
                select: { id: true }
              });

              if (!activeAccount) {
                isClosed = true;
                controller.close();
                break;
              }
            }

            if (!result) {
              safeEnqueue(controller, ": keepalive\n\n");
              continue;
            }

            for (const [, events] of result) {
              for (const [eventId, fields] of events) {
                cursor = eventId;
                const payload = parsePayload(fields);

                if (!payload) {
                  continue;
                }

                const eventType = typeof payload.type === "string" ? payload.type : "message";
                safeEnqueue(
                  controller,
                  formatSSE({
                    id: eventId,
                    event: eventType,
                    data: {
                      id: eventId,
                      ...payload
                    }
                  })
                );
              }
            }
          }
        } catch (error) {
          if (!isClosed) {
            controller.error(error);
          }
        } finally {
          clearInterval(heartbeat);
          redis?.disconnect();
        }
      },
      cancel() {
        isClosed = true;
        redis?.disconnect();
      }
    });

    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "X-Accel-Buffering": "no"
      }
    });
  } catch (error) {
    redis?.disconnect();
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

function normalizeCursor(cursor: string) {
  if (!cursor || cursor === "latest") {
    return "$";
  }

  return cursor;
}

function parsePayload(fields: string[]) {
  for (let index = 0; index < fields.length; index += 2) {
    if (fields[index] !== "payload") {
      continue;
    }

    try {
      return JSON.parse(fields[index + 1] ?? "{}") as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  return null;
}

function formatSSE(options: { id: string; event: string; data: unknown }) {
  const data = JSON.stringify(options.data).split("\n").map((line) => `data: ${line}`).join("\n");
  return `id: ${options.id}\nevent: ${options.event}\n${data}\n\n`;
}

function safeEnqueue(controller: ReadableStreamDefaultController<Uint8Array>, text: string) {
  try {
    controller.enqueue(encoder.encode(text));
  } catch {
    return;
  }
}
