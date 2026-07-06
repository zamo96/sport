import { GameRequestStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { uploadGameReportPhoto } from "@/lib/uploads";
import { hasGameRequestEnded, resolveGameRequestParticipantIds } from "@/server/game-reports";

export async function POST(request: Request, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const gameRequest = await prisma.gameRequest.findUnique({
      where: { id: params.id }
    });

    if (!gameRequest) {
      return fail("Игра не найдена", 404);
    }

    const participantIds = await resolveGameRequestParticipantIds(prisma, gameRequest);
    if (!participantIds.includes(user.id)) {
      return fail("Нет доступа", 403);
    }

    if (gameRequest.status !== GameRequestStatus.accepted) {
      return fail("Фотоотчёт можно добавить только к подтверждённой игре");
    }

    if (!hasGameRequestEnded(gameRequest)) {
      return fail("Фотоотчёт можно добавить после завершения игры");
    }

    const formData = await request.formData();
    const file = formData.get("file");

    if (
      !file ||
      typeof file === "string" ||
      typeof (file as { arrayBuffer?: unknown }).arrayBuffer !== "function"
    ) {
      return fail("Нужно выбрать файл");
    }

    const uploadedFile = file as {
      arrayBuffer: () => Promise<ArrayBuffer>;
      name?: string;
      type?: string;
    };

    const photoUrl = await uploadGameReportPhoto({
      bytes: Buffer.from(await uploadedFile.arrayBuffer()),
      originalName: uploadedFile.name || "game-report.png",
      contentType: uploadedFile.type,
      gameRequestId: gameRequest.id,
      userId: user.id
    });

    return ok({ photoUrl });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
