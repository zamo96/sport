import { Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";

type DBLike = Prisma.TransactionClient | typeof prisma;

export async function leaveRegularPairForUser(db: DBLike, pairId: string, userId: string) {
  const pair = await db.regularPair.findFirst({
    where: {
      id: pairId,
      status: "active",
      OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
    },
    include: {
      gameSearch: true,
      occurrences: {
        select: {
          id: true
        }
      }
    }
  });

  if (!pair) {
    return null;
  }

  await db.regularPair.update({
    where: { id: pair.id },
    data: {
      status: "closed"
    }
  });

  await db.regularPairOccurrence.updateMany({
    where: {
      regularPairId: pair.id,
      status: {
        in: ["pending", "confirmed"]
      }
    },
    data: {
      status: "canceled"
    }
  });

  await db.gameRequest.updateMany({
    where: {
      regularPairOccurrenceId: {
        in: pair.occurrences.map((occurrence) => occurrence.id)
      },
      status: {
        in: ["pending", "accepted"]
      }
    },
    data: {
      status: "canceled"
    }
  });

  if (userId === pair.partnerUserId) {
    await db.gameSearchResponse.updateMany({
      where: {
        gameSearchId: pair.gameSearchId,
        responderUserId: userId,
        status: "approved"
      },
      data: {
        status: "withdrawn"
      }
    });

    await db.gameSearch.update({
      where: { id: pair.gameSearchId },
      data: {
        status: "active",
        isActive: true
      }
    });

    await db.chatMessage.create({
      data: {
        matchId: pair.matchId,
        senderUserId: userId,
        text: "Игрок вышел из регулярной пары. Поиск снова открыт, можно выбрать нового партнёра."
      }
    });
  } else {
    await db.gameSearchResponse.updateMany({
      where: {
        gameSearchId: pair.gameSearchId,
        status: "approved"
      },
      data: {
        status: "rejected"
      }
    });

    await db.gameSearch.update({
      where: { id: pair.gameSearchId },
      data: {
        status: "closed",
        isActive: false
      }
    });

    await db.chatMessage.create({
      data: {
        matchId: pair.matchId,
        senderUserId: userId,
        text: "Организатор закрыл регулярную пару. Ближайшие слоты и игры по ней отменены."
      }
    });
  }

  await db.match.update({
    where: { id: pair.matchId },
    data: { updatedAt: new Date() }
  });

  return pair;
}
