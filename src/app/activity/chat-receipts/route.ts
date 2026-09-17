import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { acknowledgeChatMessages, chatReceiptSchema } from "@/server/chat-receipts";

export async function POST(request: Request) {
  try {
    const user = await requireSessionUser();
    const input = chatReceiptSchema.parse(await request.json());
    await acknowledgeChatMessages(user.id, input);
    return ok({ success: true });
  } catch (error) {
    const message = getErrorMessage(error);
    if (message === "UNAUTHORIZED") return fail("Требуется авторизация", 401);
    if (message === "CHAT_RECEIPT_FORBIDDEN") return fail("Нет доступа к сообщениям", 403);
    return fail(message);
  }
}
