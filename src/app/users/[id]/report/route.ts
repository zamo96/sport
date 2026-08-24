import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { createContentReportSchema } from "@/lib/validators";
import { createUserContentReport } from "@/server/content-reports";

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = createContentReportSchema.parse(await request.json());
    return ok({ report: await createUserContentReport(user.id, params.id, body) }, { status: 201 });
  } catch (error) {
    const message = getErrorMessage(error);
    if (message === "UNAUTHORIZED") return fail("Требуется авторизация", 401);
    if (message === "REPORTED_USER_NOT_FOUND") return fail("Пользователь не найден", 404);
    if (message === "SELF_REPORT_FORBIDDEN") return fail("Нельзя пожаловаться на самого себя");
    return fail(message);
  }
}
