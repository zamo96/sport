import type { CourtSetting, CourtStatus, Sport, Surface } from "@prisma/client";

export type AdminClubStatus = CourtStatus;

export type AdminClubSummary = {
  id: string;
  name: string;
  address: string;
  city: string;
  district: string | null;
  locationLat: number;
  locationLng: number;
  status: AdminClubStatus;
  surface: Surface;
  setting: CourtSetting;
  supportedSports: Sport[];
  photoUrl: string | null;
  priceRange: string;
  rating: number | null;
  sourceType: string;
  sourceExternalId: string | null;
  lastCheckedAt: string | null;
  updatedAt: string;
  pendingProposalCount: number;
  manualOverrideFields: string[];
};

export type AdminClub = AdminClubSummary & {
  nearestMetroId: string | null;
  metroIds: string[];
  metroNames: string[];
  phone: string | null;
  workingHours: string | null;
  yandexMapsUrl: string | null;
  websiteUrl: string | null;
  bookingUrl: string | null;
  about: string | null;
  amenities: string[];
  messengerType: string | null;
  messengerUrl: string | null;
  photoUrls: string[];
  sourceUrl: string | null;
  syncHash: string | null;
  normalizedName: string | null;
  normalizedAddress: string | null;
  websiteContentHash: string | null;
  lastSeenAt: string | null;
  websiteLastCheckedAt: string | null;
  websiteLastChangedAt: string | null;
  createdAt: string;
  usageCounts: {
    members: number;
    gameRequests: number;
    gameSearches: number;
    regularPairs: number;
    personalActivities: number;
  };
  manualStatusOverride: boolean;
  moderatedAt: string | null;
  moderatedByEmail: string | null;
};

export type AdminClubAuditLog = {
  id: string;
  action: string;
  actorEmail: string;
  reason: string | null;
  before: unknown;
  after: unknown;
  createdAt: string;
};

export type AdminClubPagination = {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
};

export type AdminClubFilters = {
  cities: string[];
  sourceTypes: string[];
};
