import { GameSearchResponseStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { isAdminUser } from "@/lib/admin";
import { fail, getErrorMessage } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { readChatImage } from "@/server/chat-media";

export async function GET(_: Request, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const asset = await prisma.chatMediaAsset.findUnique({
      where: { id: params.id },
      include: {
        chatMessageMedia: {
          select: {
            chatMessage: {
              select: {
                match: {
                  select: {
                    user1Id: true,
                    user2Id: true
                  }
                }
              }
            }
          }
        },
        searchMessageMedia: {
          select: {
            gameSearchMessage: {
              select: {
                gameSearch: {
                  select: {
                    createdByUserId: true,
                    responses: {
                      where: {
                        status: GameSearchResponseStatus.approved
                      },
                      select: {
                        responderUserId: true
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    });

    if (!asset) {
      return fail("Медиа не найдено", 404);
    }

    const match = asset.chatMessageMedia?.chatMessage.match;
    const search = asset.searchMessageMedia?.gameSearchMessage.gameSearch;
    const canAccess =
      isAdminUser(user) ||
      asset.uploaderUserId === user.id ||
      match?.user1Id === user.id ||
      match?.user2Id === user.id ||
      search?.createdByUserId === user.id ||
      search?.responses.some((response) => response.responderUserId === user.id);

    if (!canAccess) {
      return fail("Нет доступа", 403);
    }

    const bytes = await readChatImage(asset.storageKey);
    return new Response(new Uint8Array(bytes), {
      headers: {
        "Content-Type": asset.mimeType,
        "Content-Length": String(asset.byteSize),
        "Cache-Control": "private, no-store",
        "Content-Disposition": "inline",
        "X-Content-Type-Options": "nosniff"
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
