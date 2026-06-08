import { prisma } from "@/lib/prisma";
import { haversineDistanceKm } from "@/lib/geo";
import {
  buildDiscoverExplainabilityReasons,
  type CandidateUser,
  scoreCandidates,
  type DiscoverFilters
} from "@/lib/scoring";
import { courtSupportsSport } from "@/lib/courts";
import { DAY_LABELS, SPORT_LABELS, getTimePreferenceLabel } from "@/lib/constants";
import { getDiscoverCandidates } from "@/server/discover";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";
import { normalizeSports } from "@/lib/sport-levels";
import { serializeUserPreview } from "@/server/serializers";

async function closeExpiredHotSearches() {
  await prisma.gameSearch.updateMany({
    where: {
      searchType: "hot",
      isActive: true,
      hotStartsAt: {
        lte: new Date()
      }
    },
    data: {
      isActive: false,
      status: "closed"
    }
  });
}

export async function getViewerWithGuard(userId: string) {
  return prisma.user.findUnique({
    where: { id: userId }
  });
}

export async function getDiscoverPageData(userId: string, filters: DiscoverFilters = {}) {
  const [viewer, candidates] = await Promise.all([
    getViewerWithGuard(userId),
    getDiscoverCandidates(userId, filters)
  ]);

  return {
    viewer,
    candidates
  };
}

export async function getSeekingPlayers(userId: string, filters: DiscoverFilters = {}) {
  await closeExpiredHotSearches();
  return getDiscoverCandidates(userId, {
    ...filters,
    view: "seeking"
  });
}

export async function getMyGameSearchResponses(userId: string) {
  await closeExpiredHotSearches();

  return prisma.gameSearchResponse.findMany({
    where: {
      responderUserId: userId
    },
    include: {
      gameSearch: {
        include: {
          createdByUser: true,
          preferredCourt: true,
          regularPair: true
        }
      }
    },
    orderBy: {
      updatedAt: "desc"
    },
    take: 30
  });
}

export async function getIncomingLikePlayers(userId: string, filters: DiscoverFilters = {}) {
  const viewer = await prisma.user.findUnique({
    where: { id: userId }
  });

  if (!viewer) {
    return [];
  }

  const likes = await prisma.swipe.findMany({
    where: {
      toUserId: userId,
      action: {
        in: ["like", "superlike"]
      },
      fromUser: {
        onboardingCompleted: true,
        isVerified: true,
        blockedUsers: {
          none: {
            blockedUserId: userId
          }
        },
        blockingUsers: {
          none: {
            blockerUserId: userId
          }
        }
      }
    },
    include: {
      fromUser: {
        include: {
          swipesReceived: {
            where: {
              fromUserId: userId
            },
            select: {
              id: true,
              fromUserId: true
            }
          },
          gameSearches: {
            where: {
              isActive: true
            },
            include: {
              preferredCourt: true,
              responses: {
                where: {
                  responderUserId: userId
                }
              }
            },
            orderBy: {
              createdAt: "desc"
            },
            take: 1
          }
        }
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });

  const incomingUsers = likes
    .filter((like) => !like.fromUser.swipesReceived.some((swipe) => swipe.fromUserId === userId))
    .map((like) => like.fromUser);

  const scored = getDiscoverCandidatesFromUsers(viewer, incomingUsers, {
    ...filters,
    view: undefined
  });

  return scored;
}

export async function getHotPlayers(userId: string, filters: DiscoverFilters = {}) {
  await closeExpiredHotSearches();
  return getDiscoverCandidates(userId, {
    ...filters,
    view: "hot"
  });
}

export async function getGameSearchesForUser(userId: string) {
  await closeExpiredHotSearches();
  const pairIds = await prisma.regularPair.findMany({
    where: {
      OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
    },
    select: {
      id: true
    }
  });
  await Promise.all(pairIds.map((pair) => syncRegularPairOccurrences(prisma, pair.id)));

  return prisma.gameSearch.findMany({
    where: {
      createdByUserId: userId
    },
    include: {
      preferredCourt: true,
      regularPair: {
        include: {
          partnerUser: true,
          match: true,
          preferredCourt: true,
          occurrences: {
            include: {
              proposedCourt: true,
              gameRequest: {
                include: {
                  proposedCourt: true
                }
              },
              confirmations: {
                include: {
                  user: true
                }
              }
            },
            orderBy: {
              scheduledAt: "asc"
            }
          }
        }
      },
      responses: {
        include: {
          responderUser: true
        },
        orderBy: [
          { status: "asc" },
          { createdAt: "asc" }
        ]
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });
}

export async function getRegularPairForUser(userId: string, regularPairId: string) {
  await closeExpiredHotSearches();
  await syncRegularPairOccurrences(prisma, regularPairId);

  return prisma.regularPair.findFirst({
    where: {
      id: regularPairId,
      OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
    },
    include: {
      preferredCourt: true,
      createdByUser: true,
      partnerUser: true,
      match: true,
      occurrences: {
        include: {
          proposedCourt: true,
          gameRequest: {
            include: {
              proposedCourt: true
            }
          },
          confirmations: {
            include: {
              user: true
            }
          }
        },
        orderBy: {
          scheduledAt: "asc"
        }
      },
      gameSearch: {
        include: {
          responses: {
            include: {
              responderUser: true
            },
            orderBy: [{ status: "asc" }, { createdAt: "asc" }]
          }
        }
      }
    }
  });
}

export async function getActiveRegularPairsForUser(userId: string) {
  const pairIds = await prisma.regularPair.findMany({
    where: {
      status: "active",
      OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
    },
    select: {
      id: true
    }
  });

  await Promise.all(pairIds.map((pair) => syncRegularPairOccurrences(prisma, pair.id)));

  return prisma.regularPair.findMany({
    where: {
      status: "active",
      OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
    },
    include: {
      preferredCourt: true,
      createdByUser: true,
      partnerUser: true,
      occurrences: {
        where: {
          scheduledAt: {
            gt: new Date()
          }
        },
        include: {
          proposedCourt: true,
          gameRequest: {
            include: {
              proposedCourt: true
            }
          },
          confirmations: {
            include: {
              user: true
            }
          }
        },
        orderBy: {
          scheduledAt: "asc"
        },
        take: 3
      }
    },
    orderBy: {
      updatedAt: "desc"
    }
  });
}

export async function getActiveSearchesCount(userId: string) {
  await closeExpiredHotSearches();

  return prisma.gameSearch.count({
    where: {
      createdByUserId: userId,
      isActive: true
    }
  });
}

export async function getIncomingLikesCount(userId: string) {
  const incomingLikes = await prisma.swipe.findMany({
    where: {
      toUserId: userId,
      action: {
        in: ["like", "superlike"]
      }
    },
    select: {
      fromUserId: true,
      fromUser: {
        select: {
          blockedUsers: {
            where: {
              blockedUserId: userId
            },
            select: { id: true }
          },
          blockingUsers: {
            where: {
              blockerUserId: userId
            },
            select: { id: true }
          }
        }
      }
    }
  });

  const outgoing = await prisma.swipe.findMany({
    where: {
      fromUserId: userId
    },
    select: {
      toUserId: true
    }
  });

  const respondedIds = new Set(outgoing.map((swipe) => swipe.toUserId));

  return incomingLikes.filter(
    (like) =>
      !respondedIds.has(like.fromUserId) &&
      like.fromUser.blockedUsers.length === 0 &&
      like.fromUser.blockingUsers.length === 0
  ).length;
}

export async function getHotNotificationsCount(userId: string) {
  await closeExpiredHotSearches();

  const viewer = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      preferredSports: true,
      lastNotificationsSeenAt: true
    }
  });

  if (!viewer) {
    return 0;
  }

  const viewerSports = normalizeSports(viewer.preferredSports);
  const seenAt = viewer.lastNotificationsSeenAt ?? new Date(0);

  return prisma.gameSearch.count({
    where: {
      createdAt: {
        gt: seenAt
      },
      isActive: true,
      searchType: "hot",
      hotStartsAt: {
        gt: new Date()
      },
      sport: {
        in: viewerSports
      },
      createdByUserId: {
        not: userId
      },
      responses: {
        none: {
          responderUserId: userId
        }
      }
    }
  });
}

export async function getNotificationsForUser(userId: string) {
  await closeExpiredHotSearches();

  const viewer = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      preferredSports: true,
      lastInboxSeenAt: true,
      lastNotificationsSeenAt: true,
      notificationMatches: true,
      notificationMessages: true
    }
  });

  if (!viewer) {
    return [];
  }

  const seenAt = viewer.lastInboxSeenAt ?? new Date(0);
  const notificationsSeenAt = viewer.lastNotificationsSeenAt ?? new Date(0);
  const viewerSports = normalizeSports(viewer.preferredSports);

  const [incomingLikes, searchResponsesToMySearches, myApplicationUpdates, hotEvents, newMatches, unreadMessages] = await Promise.all([
    prisma.swipe.findMany({
      where: {
        toUserId: userId,
        action: {
          in: ["like", "superlike"]
        },
        fromUser: {
          onboardingCompleted: true,
          isVerified: true
        }
      },
      include: {
        fromUser: true
      },
      orderBy: {
        createdAt: "desc"
      },
      take: 20
    }),
    prisma.gameSearchResponse.findMany({
      where: {
        gameSearch: {
          createdByUserId: userId,
          isActive: true,
          status: {
            in: ["active", "in_review"]
          }
        },
        status: "pending"
      },
      include: {
        responderUser: true,
        gameSearch: true
      },
      orderBy: {
        createdAt: "desc"
      },
      take: 20
    }),
    prisma.gameSearchResponse.findMany({
      where: {
        responderUserId: userId,
        status: {
          in: ["approved", "rejected"]
        }
      },
      include: {
        gameSearch: {
          include: {
            createdByUser: true,
            preferredCourt: true,
            regularPair: true
          }
        }
      },
      orderBy: {
        updatedAt: "desc"
      },
      take: 20
    }),
    prisma.gameSearch.findMany({
      where: {
        createdAt: {
          gt: notificationsSeenAt
        },
        isActive: true,
        searchType: "hot",
        hotStartsAt: {
          gt: new Date()
        },
        sport: {
          in: viewerSports
        },
        createdByUserId: {
          not: userId
        },
        responses: {
          none: {
            responderUserId: userId
          }
        }
      },
      include: {
        createdByUser: true,
        preferredCourt: true
      },
      orderBy: {
        createdAt: "desc"
      },
      take: 20
    }),
    viewer.notificationMatches
      ? prisma.match.findMany({
          where: {
            status: "active",
            createdAt: {
              gt: seenAt
            },
            OR: [{ user1Id: userId }, { user2Id: userId }]
          },
          include: {
            user1: true,
            user2: true
          },
          orderBy: {
            createdAt: "desc"
          },
          take: 20
        })
      : Promise.resolve([]),
    viewer.notificationMessages
      ? prisma.chatMessage.findMany({
          where: {
            createdAt: {
              gt: seenAt
            },
            senderUserId: {
              not: userId
            },
            match: {
              status: "active",
              OR: [{ user1Id: userId }, { user2Id: userId }]
            }
          },
          include: {
            senderUser: true,
            match: {
              include: {
                user1: true,
                user2: true
              }
            }
          },
          orderBy: {
            createdAt: "desc"
          },
          take: 50
        })
      : Promise.resolve([])
  ]);

  const outgoingSwipes = await prisma.swipe.findMany({
    where: {
      fromUserId: userId
    },
    select: {
      toUserId: true
    }
  });

  const respondedIds = new Set(outgoingSwipes.map((swipe) => swipe.toUserId));
  const latestUnreadMessagesByConversation = new Map<string, (typeof unreadMessages)[number]>();

  for (const message of unreadMessages) {
    const conversationKey = message.gameRequestId ?? `match:${message.matchId}`;

    if (!latestUnreadMessagesByConversation.has(conversationKey)) {
      latestUnreadMessagesByConversation.set(conversationKey, message);
    }
  }

  const notifications = [
    ...newMatches.map((match) => {
      const otherUser = match.user1Id === userId ? match.user2 : match.user1;

      return {
        id: `match-${match.id}`,
        type: "new_match" as const,
        createdAt: match.createdAt,
        title: `Новый мэтч с ${otherUser.name ?? "игроком"}`,
        description: "Открой чат и договорись о времени, формате и корте.",
        href: `/inbox/${match.id}`
      };
    }),
    ...Array.from(latestUnreadMessagesByConversation.values()).map((message) => {
      const otherUser = message.match.user1Id === userId ? message.match.user2 : message.match.user1;

      return {
        id: `message-${message.id}`,
        type: "new_message" as const,
        createdAt: message.createdAt,
        title: message.gameRequestId
          ? `Обновление по игре от ${message.senderUser.name ?? otherUser.name ?? "игрока"}`
          : `Новое сообщение от ${message.senderUser.name ?? otherUser.name ?? "игрока"}`,
        description: message.text.length > 120 ? `${message.text.slice(0, 117)}...` : message.text,
        href: message.gameRequestId ? `/play/games/${message.gameRequestId}` : `/inbox/${message.matchId}`
      };
    }),
    ...incomingLikes
      .filter((like) => !respondedIds.has(like.fromUserId))
      .map((like) => ({
        id: `like-${like.id}`,
        type: "incoming_like" as const,
        createdAt: like.createdAt,
        title: `${like.fromUser.name ?? "Игрок"} хочет с тобой сыграть`,
        description: "Открой вкладку «Хотят с тобой», чтобы ответить лайком или пропустить.",
        href: `/discover?view=likes&highlight=${like.fromUserId}`
      })),
    ...searchResponsesToMySearches.map((response) => ({
      id: `response-${response.id}`,
      type: "search_response" as const,
      createdAt: response.createdAt,
      title: `${response.responderUser.name ?? "Игрок"} откликнулся на твой поиск`,
      description: "Можно открыть свои поиски и решить, подтверждать ли отклик.",
      href: "/play/searches"
    })),
    ...myApplicationUpdates.map((response) => ({
      id: `application-${response.id}`,
      type: "application_result" as const,
      createdAt: response.updatedAt,
      status: response.status,
      title:
        response.status === "approved"
          ? `Твой отклик одобрен: ${response.gameSearch.createdByUser.name ?? "организатор"}`
          : `Твой отклик отклонён: ${response.gameSearch.createdByUser.name ?? "организатор"}`,
      description:
        response.status === "approved"
          ? `${SPORT_LABELS[response.gameSearch.sport]} · ${
              response.gameSearch.preferredCourt?.name ?? "клуб подберут позже"
            } · ${buildNotificationSearchTime(response.gameSearch)}`
          : `${SPORT_LABELS[response.gameSearch.sport]} · ${
              response.gameSearch.preferredCourt?.name ?? "клуб не указан"
            } · ${buildNotificationSearchTime(response.gameSearch)}`,
      href:
        response.status === "approved"
          ? response.gameSearch.regularPair?.matchId
            ? `/inbox/${response.gameSearch.regularPair.matchId}`
            : `/discover?view=seeking&highlight=${response.gameSearch.id}`
          : `/discover?view=seeking&highlight=${response.gameSearch.id}`
    })),
    ...hotEvents.map((search) => ({
      id: `hot-${search.id}`,
      type: "hot_event" as const,
      createdAt: search.createdAt,
      title: `${search.createdByUser.name ?? "Игрок"} ищет срочно ${SPORT_LABELS[search.sport]}`,
      description: search.preferredCourt
        ? `Есть площадка: ${search.preferredCourt.name}. Проверь вкладку «Срочно».`
        : "Новое срочное событие по одному из твоих видов спорта.",
      href: `/discover?view=hot&highlight=${search.id}`
    }))
  ];

  return notifications.sort((left, right) => right.createdAt.getTime() - left.createdAt.getTime()).slice(0, 30);
}

function buildNotificationSearchTime(search: {
  searchType: "regular" | "hot";
  hotStartsAt?: Date | null;
  preferredDays?: unknown;
  preferredTimeRanges?: unknown;
}) {
  if (search.searchType === "hot" && search.hotStartsAt) {
    return search.hotStartsAt.toLocaleString("ru-RU", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    });
  }

  const days = Array.isArray(search.preferredDays) ? search.preferredDays.filter((item): item is string => typeof item === "string") : [];
  const ranges = Array.isArray(search.preferredTimeRanges)
    ? search.preferredTimeRanges.filter((item): item is string => typeof item === "string")
    : [];

  const dayLabel = days
    .slice(0, 2)
    .map((day) => DAY_LABELS[day as keyof typeof DAY_LABELS] ?? day)
    .join(", ");
  const rangeLabel = ranges
    .slice(0, 2)
    .map(getTimePreferenceLabel)
    .join(", ");

  return [dayLabel, rangeLabel].filter(Boolean).join(" · ") || "время уточняется";
}

export async function getUpcomingGamesForUser(userId: string) {
  const pairIds = await prisma.regularPair.findMany({
    where: {
      status: "active",
      OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
    },
    select: {
      id: true
    }
  });

  await Promise.all(pairIds.map((pair) => syncRegularPairOccurrences(prisma, pair.id)));

  const [gameRequests, regularOccurrences] = await Promise.all([
    prisma.gameRequest.findMany({
      where: {
        status: "accepted",
        proposedDatetime: {
          gte: new Date()
        },
        OR: [{ createdByUserId: userId }, { matchedUserId: userId }]
      },
      include: {
        proposedCourt: true,
        createdByUser: true,
        matchedUser: true,
        match: true,
        sharedInvites: {
          where: {
            status: "accepted"
          },
          include: {
            matchedUser: true
          }
        }
      },
      orderBy: {
        proposedDatetime: "asc"
      },
      take: 5
    }),
    prisma.regularPairOccurrence.findMany({
      where: {
        status: "confirmed",
        gameRequest: null,
        scheduledAt: {
          gte: new Date()
        },
        regularPair: {
          status: "active",
          OR: [{ createdByUserId: userId }, { partnerUserId: userId }]
        }
      },
      include: {
        proposedCourt: true,
        regularPair: {
          include: {
            preferredCourt: true,
            createdByUser: true,
            partnerUser: true,
            match: true
          }
        }
      },
      orderBy: {
        scheduledAt: "asc"
      },
      take: 5
    })
  ]);

  const normalizedOccurrences = regularOccurrences.map((occurrence) => ({
    id: occurrence.id,
    matchId: occurrence.regularPair.matchId,
    status: "accepted" as const,
    outcome: null,
    outcomeUpdatedAt: null,
    proposedDatetime: occurrence.scheduledAt,
    durationMinutes: occurrence.durationMinutes ?? 90,
    comment: occurrence.regularPair.comment ?? "Слот регулярной игры подтверждён обеими сторонами.",
    sport: occurrence.sport,
    format: occurrence.format,
    createdByUserId: occurrence.regularPair.createdByUserId,
    matchedUserId: occurrence.regularPair.partnerUserId,
    proposedCourt: occurrence.proposedCourt ??
      occurrence.regularPair.preferredCourt ?? {
        name: "Клуб уточняется",
        address: "Подберите удобный клуб в чате"
      },
    createdByUser: occurrence.regularPair.createdByUser,
    matchedUser: occurrence.regularPair.partnerUser,
    participants: [
      serializeUserPreview(occurrence.regularPair.createdByUser),
      serializeUserPreview(occurrence.regularPair.partnerUser)
    ],
    match: occurrence.regularPair.match,
    regularPairId: occurrence.regularPairId,
    sourceType: "regular_occurrence" as const
  }));

  const searchLobbyIdsByRequestId = await resolveUpcomingSearchLobbyIds(gameRequests);

  const normalizedRequests = gameRequests.map((request) => ({
    ...request,
    searchLobbyId: searchLobbyIdsByRequestId.get(request.id) ?? null,
    participants: [
      serializeUserPreview(request.createdByUser),
      serializeUserPreview(request.matchedUser),
      ...request.sharedInvites.map((invite) => serializeUserPreview(invite.matchedUser))
    ].filter((participant, index, array) => array.findIndex((candidate) => candidate.id === participant.id) === index)
  }));

  return [...normalizedRequests, ...normalizedOccurrences]
    .sort((left, right) => left.proposedDatetime.getTime() - right.proposedDatetime.getTime())
    .slice(0, 5);
}

async function resolveUpcomingSearchLobbyIds(
  requests: Array<
    Awaited<ReturnType<typeof prisma.gameRequest.findMany>>[number] & {
      sharedInvites: Array<{ matchedUser: Parameters<typeof serializeUserPreview>[0] }>;
    }
  >
) {
  const result = new Map<string, string>();
  const groupRequests = requests.filter((request) => request.sharedInvites.length > 0);

  await Promise.all(
    groupRequests.map(async (request) => {
      const linkedSearch = await prisma.gameSearch.findFirst({
        where: {
          createdByUserId: request.createdByUserId,
          scheduledAt: request.proposedDatetime,
          scheduledCourtId: request.proposedCourtId,
          sport: request.sport,
          format: request.format,
          playersNeeded: {
            gt: 1
          }
        },
        select: {
          id: true
        },
        orderBy: {
          updatedAt: "desc"
        }
      });

      if (linkedSearch?.id) {
        result.set(request.id, linkedSearch.id);
      }
    })
  );

  return result;
}

export async function getMatchesForUser(userId: string) {
  return prisma.match.findMany({
    where: {
      status: "active",
      OR: [{ user1Id: userId }, { user2Id: userId }]
    },
    include: {
      user1: true,
      user2: true,
      messages: {
        include: {
          senderUser: true
        },
        where: {
          gameRequestId: null
        },
        orderBy: {
          createdAt: "desc"
        },
        take: 1
      },
      gameRequests: {
        include: {
          proposedCourt: true,
          createdByUser: true,
          matchedUser: true
        },
        orderBy: {
          createdAt: "desc"
        },
        take: 1
      }
    },
    orderBy: {
      updatedAt: "desc"
    }
  });
}

export async function getMatchDetail(matchId: string, userId: string) {
  return prisma.match.findFirst({
    where: {
      id: matchId,
      status: "active",
      OR: [{ user1Id: userId }, { user2Id: userId }]
    },
    include: {
      user1: true,
      user2: true,
      messages: {
        include: {
          senderUser: true
        },
        where: {
          gameRequestId: null
        },
        orderBy: {
          createdAt: "asc"
        }
      },
      gameRequests: {
        include: {
          proposedCourt: true,
          createdByUser: true,
          matchedUser: true
        },
        orderBy: {
          createdAt: "desc"
        }
      }
    }
  });
}

export async function getGameRequestDetail(gameRequestId: string, userId: string) {
  return prisma.gameRequest.findFirst({
    where: {
      id: gameRequestId,
      OR: [{ createdByUserId: userId }, { matchedUserId: userId }]
    },
    include: {
      proposedCourt: true,
      messages: {
        include: {
          senderUser: true
        },
        orderBy: {
          createdAt: "asc"
        }
      },
      createdByUser: true,
      matchedUser: true,
      match: {
        include: {
          user1: true,
          user2: true,
          messages: {
            include: {
              senderUser: true
            },
            where: {
              gameRequestId: null
            },
            orderBy: {
              createdAt: "asc"
            }
          },
          gameRequests: {
            include: {
              proposedCourt: true,
              createdByUser: true,
              matchedUser: true
            },
            orderBy: {
              createdAt: "desc"
            }
          }
        }
      }
    }
  });
}

export type CourtsFilters = {
  sport?: import("@prisma/client").Sport;
  q?: string;
  district?: string;
  maxDistanceKm?: number;
  city?: string;
};

export async function getCourtsForUser(
  userId: string,
  filters: CourtsFilters = {}
) {
  const user = await prisma.user.findUnique({
    where: { id: userId }
  });

  if (!user) {
    return [];
  }

  const preferredDistricts = resolvePreferredDistricts(user.preferredDistricts, user.district);

  const courts = await prisma.court.findMany({
    where: {
      city: filters.city,
      ...(filters.district ? { district: filters.district } : {}),
      ...(filters.q
        ? {
            OR: [
              {
                name: {
                  contains: filters.q,
                  mode: "insensitive"
                }
              },
              {
                address: {
                  contains: filters.q,
                  mode: "insensitive"
                }
              },
              {
                district: {
                  contains: filters.q,
                  mode: "insensitive"
                }
              }
            ]
          }
        : {})
    },
    include: {
      nearestMetro: true
    },
    orderBy: [{ rating: "desc" }, { name: "asc" }]
  });

  return courts
    .map((court) => ({
      ...court,
      distanceKm: haversineDistanceKm(
        user.homeLat != null && user.homeLng != null ? { lat: user.homeLat, lng: user.homeLng } : null,
        { lat: court.locationLat, lng: court.locationLng }
      )
    }))
    .filter((court) =>
      courtSupportsSport(court.supportedSports, filters.sport) &&
      (filters.maxDistanceKm && court.distanceKm != null
        ? court.distanceKm <= filters.maxDistanceKm
        : true
      )
    )
    .sort((first, second) => {
      const firstDistrictRank = districtRank(preferredDistricts, first.district);
      const secondDistrictRank = districtRank(preferredDistricts, second.district);

      if (firstDistrictRank !== secondDistrictRank) {
        return firstDistrictRank - secondDistrictRank;
      }

      const firstDistance = first.distanceKm ?? Number.POSITIVE_INFINITY;
      const secondDistance = second.distanceKm ?? Number.POSITIVE_INFINITY;

      if (firstDistance !== secondDistance) {
        return firstDistance - secondDistance;
      }

      return (second.rating ?? 0) - (first.rating ?? 0);
    });
}

function resolvePreferredDistricts(preferredDistricts: unknown, fallbackDistrict?: string | null) {
  const districts = Array.isArray(preferredDistricts)
    ? preferredDistricts.filter((district): district is string => typeof district === "string" && district.trim().length > 0)
    : [];

  if (districts.length > 0) {
    return Array.from(new Set(districts));
  }

  return fallbackDistrict ? [fallbackDistrict] : [];
}

function districtRank(preferredDistricts: string[], district?: string | null) {
  if (!district) {
    return Number.POSITIVE_INFINITY;
  }

  const index = preferredDistricts.indexOf(district);
  return index === -1 ? Number.POSITIVE_INFINITY : index;
}

function getDiscoverCandidatesFromUsers(
  viewer: Awaited<ReturnType<typeof prisma.user.findUnique>>,
  users: Array<{
    id: string;
    name: string | null;
    age: number | null;
    gender: import("@prisma/client").Gender | null;
    city: string | null;
    bio: string | null;
    avatarUrl: string | null;
    homeLat: number | null;
    homeLng: number | null;
    tennisLevel: number | null;
    preferredSports: unknown;
    sportLevels: unknown;
    preferredPlayFormat: import("@prisma/client").PlayFormat;
    preferredSurface: import("@prisma/client").Surface;
    availableDays: unknown;
    availableTimeRanges: unknown;
    availableTimeSlots: unknown;
    searchRadiusKm: number;
    isLookingForGame: boolean;
    gameSearches?: unknown;
  }>,
  filters: DiscoverFilters
) {
  if (!viewer) {
    return [];
  }

  const viewerProfile = {
    id: viewer.id,
    name: viewer.name,
    age: viewer.age,
    gender: viewer.gender,
    city: viewer.city,
    district: viewer.district,
    preferredDistricts: viewer.preferredDistricts,
    bio: viewer.bio,
    avatarUrl: viewer.avatarUrl,
    homeLat: viewer.homeLat,
    homeLng: viewer.homeLng,
    tennisLevel: viewer.tennisLevel,
    preferredSports: viewer.preferredSports,
    sportLevels: viewer.sportLevels,
    preferredPlayFormat: viewer.preferredPlayFormat,
    preferredSurface: viewer.preferredSurface,
    availableDays: viewer.availableDays,
    availableTimeRanges: viewer.availableTimeRanges,
    availableTimeSlots: viewer.availableTimeSlots,
    searchRadiusKm: viewer.searchRadiusKm,
    isLookingForGame: viewer.isLookingForGame
  } satisfies CandidateUser;

  const scored = scoreCandidates(viewerProfile, users as Array<any>, filters);

  return scored.map((candidate) => ({
    ...candidate,
    explainabilityReasons: buildDiscoverExplainabilityReasons(viewerProfile, candidate, filters)
  }));
}
