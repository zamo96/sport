import type { Gender, PlayFormat, Sport, Surface } from "@prisma/client";

export type AdminAccountStatus = "active" | "deactivated";

export type AdminPlayer = {
  id: string;
  email: string;
  name: string | null;
  age: number | null;
  gender: Gender | null;
  city: string | null;
  district: string | null;
  preferredDistricts: string[];
  tennisLevel: number | null;
  preferredSports: Sport[];
  sportLevels: Partial<Record<Sport, number | null>>;
  preferredPlayFormat: PlayFormat;
  preferredSurface: Surface;
  bio: string | null;
  avatarUrl: string | null;
  profilePhotoUrls: string[];
  profileVideoUrls: string[];
  availableDays: string[];
  availableTimeRanges: string[];
  availabilityByDay: Partial<Record<string, string[]>>;
  isLookingForGame: boolean;
  isVerified: boolean;
  onboardingCompleted: boolean;
  accountStatus: AdminAccountStatus;
  deactivatedAt: string | null;
  deactivationReason: string | null;
  createdAt: string;
  updatedAt: string;
  lastActiveAt: string | null;
};

export type AdminPlayerAuditLog = {
  id: string;
  action: "PROFILE_UPDATED" | "ACCOUNT_DEACTIVATED" | "ACCOUNT_REACTIVATED" | string;
  actorEmail: string;
  reason: string | null;
  before: unknown;
  after: unknown;
  createdAt: string;
};

export type AdminPlayerPagination = {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
};
