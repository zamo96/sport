import { GameRequestStatus, Prisma, SwipeAction, type Match, type Swipe } from "@prisma/client";

export function normalizeMatchPair(userAId: string, userBId: string) {
  return [userAId, userBId].sort();
}

export async function createSwipeAndMaybeMatch(
  db: Pick<Prisma.TransactionClient, "swipe" | "match">,
  fromUserId: string,
  toUserId: string,
  action: SwipeAction
) {
  const swipe = await db.swipe.upsert({
    where: {
      fromUserId_toUserId: {
        fromUserId,
        toUserId
      }
    },
    update: {
      action
    },
    create: {
      fromUserId,
      toUserId,
      action
    }
  });

  if (action === SwipeAction.dislike) {
    return { swipe, match: null };
  }

  const reverse = await db.swipe.findUnique({
    where: {
      fromUserId_toUserId: {
        fromUserId: toUserId,
        toUserId: fromUserId
      }
    }
  });

  if (!reverse || (reverse.action !== SwipeAction.like && reverse.action !== SwipeAction.superlike)) {
    return { swipe, match: null };
  }

  const [user1Id, user2Id] = normalizeMatchPair(fromUserId, toUserId);

  const match = await db.match.upsert({
    where: {
      user1Id_user2Id: {
        user1Id,
        user2Id
      }
    },
    update: {
      status: "active"
    },
    create: {
      user1Id,
      user2Id
    }
  });

  return { swipe, match };
}

export async function ensureMatchForUsers(
  db: Pick<Prisma.TransactionClient, "match">,
  userAId: string,
  userBId: string
) {
  const [user1Id, user2Id] = normalizeMatchPair(userAId, userBId);

  return db.match.upsert({
    where: {
      user1Id_user2Id: {
        user1Id,
        user2Id
      }
    },
    update: {
      status: "active",
      updatedAt: new Date()
    },
    create: {
      user1Id,
      user2Id,
      status: "active"
    }
  });
}

export function canTransitionGameRequest(currentStatus: GameRequestStatus, nextStatus: GameRequestStatus) {
  switch (currentStatus) {
    case GameRequestStatus.pending:
      return (
        nextStatus === GameRequestStatus.accepted ||
        nextStatus === GameRequestStatus.declined ||
        nextStatus === GameRequestStatus.canceled
      );
    case GameRequestStatus.accepted:
    case GameRequestStatus.declined:
      return nextStatus === GameRequestStatus.canceled;
    case GameRequestStatus.canceled:
      return false;
    default:
      return false;
  }
}

export function canUpdateGameRequestOutcome(currentStatus: GameRequestStatus) {
  return currentStatus === GameRequestStatus.accepted;
}

export type SwipeWithMatch = {
  swipe: Swipe;
  match: Match | null;
};
