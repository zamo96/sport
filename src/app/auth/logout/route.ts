import { destroySession } from "@/lib/auth";
import { fail, ok } from "@/lib/http";
import { registerPushDeviceSchema } from "@/lib/validators";
import { z } from "zod";

const logoutSchema = z.object({ pushDeviceToken: registerPushDeviceSchema.shape.token.optional() });

export async function POST(request: Request) {
  let body: z.infer<typeof logoutSchema>;
  try {
    const text = await request.text();
    body = logoutSchema.parse(text.trim() ? JSON.parse(text) : {});
  } catch {
    return fail("Invalid logout request", 400);
  }
  await destroySession(body.pushDeviceToken);
  return ok({ ok: true });
}
