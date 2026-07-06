import { SwipeAction, type Sport } from "@prisma/client";

import { prisma } from "@/lib/prisma";
import type { DiscoverFilters, ScoredCandidate } from "@/lib/scoring";

const DAY_MS = 24 * 60 * 60 * 1000;
const IMPRESSION_DEDUPE_MS = 6 * 60 * 60 * 1000;
const MAX_RECORDED_IMPRESSIONS = 30;

type RecommendationCandidate = ScoredCandidate & {
  createdAt?: Date | null;
  lastActiveAt?: Date | null;
  gameSearches?: Array<{ id: string; sport?: Sport | null; searchType?: string | null; hotStartsAt?: Date | string | null }>;
  recommendationScore?: number;
};

export type RecommendationSignals = {
  baseScore: number;
  inactiveDays: number;
  viewerImpressionCount: number;
  hoursSinceViewerLastImpression: number | null;
  candidateExposureCount: number;
  averageExposureCount: number;
  candidateInboundInterestCount: number;
  averageInboundInterestCount: number;
  hasActiveSearch: boolean;
  isLookingForGame: boolean;
  createdAt?: Date | null;
  lastActiveAt?: Date | null;
};

export function calculateRecommendationScore(signals: RecommendationSignals) {
  const reentryFactor = signals.inactiveDays >= 7 ? 1 : signals.inactiveDays >= 3 ? 0.55 : 0;
  const activityBoost = getActivityBoost(signals.lastActiveAt) + (signals.hasActiveSearch ? 7 : signals.isLookingForGame ? 3 : 0);
  const freshnessBoost = getFreshnessBoost(signals.createdAt);
  const viewerRepeatPenalty =
    Math.min(24, signals.viewerImpressionCount * 6) +
    (signals.hoursSinceViewerLastImpression != null && signals.hoursSinceViewerLastImpression < 12 ? 10 : 0);
  const exposurePenalty = Math.min(
    18,
    Math.max(0, signals.candidateExposureCount - signals.averageExposureCount) * 1.7
  );
  const inboundPenalty = Math.min(
    16,
    Math.max(0, signals.candidateInboundInterestCount - signals.averageInboundInterestCount) * 3.2
  );
  const underexposedBoost =
    signals.candidateExposureCount <= Math.max(1, signals.averageExposureCount * 0.55) &&
    signals.candidateInboundInterestCount <= Math.max(1, signals.averageInboundInterestCount * 0.75)
      ? Math.min(9, 4 + Math.max(0, signals.averageExposureCount - signals.candidateExposureCount))
      : 0;
  const reentryBoost = reentryFactor * (activityBoost + freshnessBoost + underexposedBoost);

  return (
    signals.baseScore +
    activityBoost * 0.35 +
    freshnessBoost * 0.45 +
    underexposedBoost +
    reentryBoost -
    viewerRepeatPenalty -
    exposurePenalty -
    inboundPenalty
  );
}

export async function rerankDiscoverCandidates<T extends RecommendationCandidate>(
  viewerId: string,
  candidates: T[],
  filters: DiscoverFilters = {}
) {
  if (candidates.length === 0) {
    return candidates;
  }

  const now = new Date();
  const candidateIds = candidates.map((candidate) => candidate.id);
  const since7Days = new Date(now.getTime() - 7 * DAY_MS);
  const since14Days = new Date(now.getTime() - 14 * DAY_MS);

  const [
    lastSwipe,
    globalImpressions,
    viewerImpressions,
    inboundSwipes,
    inboundGameRequests,
    inboundSearchResponses
  ] = await Promise.all([
    prisma.swipe.findFirst({
      where: {
        fromUserId: viewerId
      },
      orderBy: {
        updatedAt: "desc"
      },
      select: {
        updatedAt: true
      }
    }),
    prisma.discoverImpression.groupBy({
      by: ["candidateUserId"],
      where: {
        candidateUserId: {
          in: candidateIds
        },
        createdAt: {
          gte: since7Days
        }
      },
      _count: {
        _all: true
      }
    }),
    prisma.discoverImpression.findMany({
      where: {
        viewerUserId: viewerId,
        candidateUserId: {
          in: candidateIds
        },
        createdAt: {
          gte: since14Days
        }
      },
      select: {
        candidateUserId: true,
        createdAt: true
      },
      orderBy: {
        createdAt: "desc"
      }
    }),
    prisma.swipe.groupBy({
      by: ["toUserId"],
      where: {
        toUserId: {
          in: candidateIds
        },
        action: {
          in: [SwipeAction.like, SwipeAction.superlike]
        },
        createdAt: {
          gte: since7Days
        }
      },
      _count: {
        _all: true
      }
    }),
    prisma.gameRequest.groupBy({
      by: ["matchedUserId"],
      where: {
        matchedUserId: {
          in: candidateIds
        },
        createdAt: {
          gte: since7Days
        }
      },
      _count: {
        _all: true
      }
    }),
    prisma.gameSearchResponse.findMany({
      where: {
        createdAt: {
          gte: since7Days
        },
        gameSearch: {
          createdByUserId: {
            in: candidateIds
          }
        }
      },
      select: {
        gameSearch: {
          select: {
            createdByUserId: true
          }
        }
      }
    })
  ]);

  const inactiveDays = lastSwipe ? Math.max(0, (now.getTime() - lastSwipe.updatedAt.getTime()) / DAY_MS) : 14;
  const exposureCounts = new Map(globalImpressions.map((row) => [row.candidateUserId, row._count._all]));
  const viewerImpressionCounts = new Map<string, number>();
  const viewerLastImpressionAt = new Map<string, Date>();
  const inboundCounts = new Map<string, number>();

  for (const impression of viewerImpressions) {
    viewerImpressionCounts.set(
      impression.candidateUserId,
      (viewerImpressionCounts.get(impression.candidateUserId) ?? 0) + 1
    );
    if (!viewerLastImpressionAt.has(impression.candidateUserId)) {
      viewerLastImpressionAt.set(impression.candidateUserId, impression.createdAt);
    }
  }

  for (const row of inboundSwipes) {
    inboundCounts.set(row.toUserId, (inboundCounts.get(row.toUserId) ?? 0) + row._count._all);
  }

  for (const row of inboundGameRequests) {
    inboundCounts.set(row.matchedUserId, (inboundCounts.get(row.matchedUserId) ?? 0) + row._count._all);
  }

  for (const response of inboundSearchResponses) {
    const ownerId = response.gameSearch.createdByUserId;
    inboundCounts.set(ownerId, (inboundCounts.get(ownerId) ?? 0) + 1);
  }

  const averageExposureCount =
    candidateIds.reduce((sum, id) => sum + (exposureCounts.get(id) ?? 0), 0) / Math.max(1, candidateIds.length);
  const averageInboundInterestCount =
    candidateIds.reduce((sum, id) => sum + (inboundCounts.get(id) ?? 0), 0) / Math.max(1, candidateIds.length);

  const ranked = candidates
    .map((candidate) => {
      const lastImpressionAt = viewerLastImpressionAt.get(candidate.id);
      const recommendationScore = calculateRecommendationScore({
        baseScore: candidate.score,
        inactiveDays,
        viewerImpressionCount: viewerImpressionCounts.get(candidate.id) ?? 0,
        hoursSinceViewerLastImpression: lastImpressionAt
          ? (now.getTime() - lastImpressionAt.getTime()) / (60 * 60 * 1000)
          : null,
        candidateExposureCount: exposureCounts.get(candidate.id) ?? 0,
        averageExposureCount,
        candidateInboundInterestCount: inboundCounts.get(candidate.id) ?? 0,
        averageInboundInterestCount,
        hasActiveSearch: hasActiveSearch(candidate),
        isLookingForGame: candidate.isLookingForGame,
        createdAt: candidate.createdAt,
        lastActiveAt: candidate.lastActiveAt
      });

      return {
        ...candidate,
        recommendationScore
      };
    })
    .sort((left, right) => {
      const rightScore = right.recommendationScore ?? right.score;
      const leftScore = left.recommendationScore ?? left.score;
      return rightScore - leftScore || (left.distanceKm ?? 999) - (right.distanceKm ?? 999);
    });

  return diversifyTopWindow(ranked, filters);
}

export async function recordDiscoverImpressions<T extends RecommendationCandidate>(
  viewerId: string,
  candidates: T[],
  source: string
) {
  const topCandidates = candidates.slice(0, MAX_RECORDED_IMPRESSIONS);

  if (topCandidates.length === 0) {
    return;
  }

  const since = new Date(Date.now() - IMPRESSION_DEDUPE_MS);
  const candidateIds = topCandidates.map((candidate) => candidate.id);
  const recent = await prisma.discoverImpression.findMany({
    where: {
      viewerUserId: viewerId,
      candidateUserId: {
        in: candidateIds
      },
      source,
      createdAt: {
        gte: since
      }
    },
    select: {
      candidateUserId: true
    }
  });
  const recentlyRecordedIds = new Set(recent.map((impression) => impression.candidateUserId));

  const impressionsToCreate = topCandidates
    .map((candidate, index) => ({
      viewerUserId: viewerId,
      candidateUserId: candidate.id,
      source,
      rank: index + 1,
      baseScore: candidate.score,
      finalScore: candidate.recommendationScore ?? candidate.score
    }))
    .filter((impression) => !recentlyRecordedIds.has(impression.candidateUserId));

  if (impressionsToCreate.length === 0) {
    return;
  }

  await prisma.discoverImpression.createMany({
    data: impressionsToCreate
  });
}

function hasActiveSearch(candidate: RecommendationCandidate) {
  return Array.isArray(candidate.gameSearches) && candidate.gameSearches.length > 0;
}

function getFreshnessBoost(createdAt?: Date | null) {
  if (!createdAt) {
    return 0;
  }

  const ageDays = (Date.now() - createdAt.getTime()) / DAY_MS;

  if (ageDays <= 7) {
    return 8;
  }

  if (ageDays <= 30) {
    return 4;
  }

  return 0;
}

function getActivityBoost(lastActiveAt?: Date | null) {
  if (!lastActiveAt) {
    return 0;
  }

  const inactiveHours = (Date.now() - lastActiveAt.getTime()) / (60 * 60 * 1000);

  if (inactiveHours <= 24) {
    return 7;
  }

  if (inactiveHours <= 72) {
    return 4;
  }

  return 0;
}

function diversifyTopWindow<T extends RecommendationCandidate>(candidates: T[], filters: DiscoverFilters) {
  if (candidates.length < 6 || filters.view === "hot") {
    return candidates;
  }

  const remaining = [...candidates];
  const result: T[] = [];
  const topWindowSize = Math.min(12, candidates.length);

  while (result.length < topWindowSize && remaining.length > 0) {
    const recentDistricts = result.slice(-4).map((candidate) => candidate.district).filter(Boolean);
    const nextIndex = remaining.findIndex((candidate, index) => {
      if (index > 7) {
        return false;
      }

      if (!candidate.district) {
        return true;
      }

      return recentDistricts.filter((district) => district === candidate.district).length < 2;
    });
    const selectedIndex = nextIndex >= 0 ? nextIndex : 0;
    const [selected] = remaining.splice(selectedIndex, 1);
    result.push(selected);
  }

  return [...result, ...remaining];
}
