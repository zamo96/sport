import type { Prisma, User } from "@prisma/client";

import {
  ANALYTICS_CONSENT_VERSION,
  PROFILE_VISIBILITY_CONSENT_VERSION,
  USER_AGREEMENT_KEY,
  USER_AGREEMENT_VERSION
} from "@/lib/legal-contract";
import { prisma } from "@/lib/prisma";
import type { ConsentUpdatePayload } from "@/lib/validators";

export class ConsentUpdateError extends Error {}

type RequestMeta = { ip?: string | null; userAgent?: string | null };

type ProfileScope = {
  visibleToGuests: boolean;
  bio: boolean;
  photos: boolean;
  videos: boolean;
  searches: boolean;
  map: boolean;
};

function profileScopeFromUser(user: User): ProfileScope {
  return {
    visibleToGuests: user.profileVisibleToGuests,
    bio: user.profileShowsBio,
    photos: user.profileShowsPhotos,
    videos: user.profileShowsVideos,
    searches: user.profileShowsSearches,
    map: user.showOnMap
  };
}

/**
 * Применяет ответ с экрана согласий или из настроек. Каждое согласие пишется
 * отдельной строкой журнала со своей версией текста: принятие соглашения,
 * согласие на показ анкеты и согласие на аналитику не смешиваются.
 */
export async function applyConsentUpdate(userId: string, payload: ConsentUpdatePayload, meta: RequestMeta = {}) {
  return prisma.$transaction(async (tx) => {
    const user = await tx.user.findUniqueOrThrow({ where: { id: userId } });
    const userData: Prisma.UserUpdateInput = {};
    const consentRows: Prisma.UserConsentCreateManyInput[] = [];
    const logged = { source: payload.source, ipAddress: meta.ip ?? null, userAgent: meta.userAgent ?? null };

    if (payload.acceptAgreementVersion) {
      await tx.userAgreementAcceptance.createMany({
        data: [
          {
            userId,
            agreementKey: USER_AGREEMENT_KEY,
            agreementVersion: payload.acceptAgreementVersion,
            personalDataConsentVersion: null,
            acceptedVia: `consent_review_${payload.source}`,
            ipAddress: logged.ipAddress,
            userAgent: logged.userAgent
          }
        ],
        skipDuplicates: true
      });
      userData.agreementVersion = USER_AGREEMENT_VERSION;
    }

    if (payload.profile) {
      const profile = payload.profile;
      if (profile.decision === "visible") {
        const fullName = profile.fullName ?? user.consentFullName;
        if (!fullName) {
          throw new ConsentUpdateError("Укажите фамилию и имя для согласия на показ анкеты");
        }
        const scope: ProfileScope = {
          visibleToGuests: profile.visibleToGuests === true,
          bio: profile.showsBio === true,
          photos: profile.showsPhotos === true,
          videos: profile.showsVideos === true,
          searches: profile.showsSearches === true,
          map: profile.showOnMap === true
        };
        Object.assign(userData, {
          profileVisibility: "visible",
          consentFullName: fullName,
          profileVisibleToGuests: scope.visibleToGuests,
          profileShowsBio: scope.bio,
          profileShowsPhotos: scope.photos,
          profileShowsVideos: scope.videos,
          profileShowsSearches: scope.searches,
          showOnMap: scope.map
        } satisfies Prisma.UserUpdateInput);
        consentRows.push({
          userId,
          kind: "profile_visibility",
          version: PROFILE_VISIBILITY_CONSENT_VERSION,
          granted: true,
          scope,
          fullName,
          ...logged
        });
      } else {
        userData.profileVisibility = "hidden";
        consentRows.push({
          userId,
          kind: "profile_visibility",
          version: PROFILE_VISIBILITY_CONSENT_VERSION,
          granted: false,
          scope: profileScopeFromUser(user),
          ...logged
        });
      }
    }

    if (payload.analytics !== undefined) {
      userData.analyticsConsent = payload.analytics;
      if (!payload.analytics) {
        // Отзыв: накопленные события больше не на чем хранить.
        await tx.userEvent.deleteMany({ where: { userId } });
      }
      consentRows.push({
        userId,
        kind: "analytics",
        version: ANALYTICS_CONSENT_VERSION,
        granted: payload.analytics,
        ...logged
      });
    }

    if (consentRows.length) {
      await tx.userConsent.createMany({ data: consentRows });
    }

    return tx.user.update({
      where: { id: userId },
      data: userData,
      include: { location: { include: { serviceArea: true } } }
    });
  });
}

/**
 * Переключатель «Показывать на карте» в профиле меняет объём уже данного
 * согласия на показ, поэтому изменение тоже попадает в журнал.
 */
export async function logMapVisibilityChange(user: User, showOnMap: boolean, meta: RequestMeta = {}) {
  if (user.profileVisibility !== "visible" || user.showOnMap === showOnMap) return;
  await prisma.userConsent.create({
    data: {
      userId: user.id,
      kind: "profile_visibility",
      version: PROFILE_VISIBILITY_CONSENT_VERSION,
      granted: true,
      scope: { ...profileScopeFromUser(user), map: showOnMap },
      fullName: user.consentFullName,
      source: "profile_settings",
      ipAddress: meta.ip ?? null,
      userAgent: meta.userAgent ?? null
    }
  });
}
