export type AdminReportUser = {
  id: string;
  email?: string | null;
  name?: string | null;
  accountStatus?: string;
  avatarUrl?: string | null;
  updatedAt?: string;
};

export type AdminContentReport = {
  id: string;
  reporterUserId: string | null;
  reporterEmail: string;
  reporterName?: string | null;
  reportedUserId: string | null;
  reportedEmail: string;
  reportedName?: string | null;
  origin: string;
  reason: string;
  details?: string | null;
  contentType: string;
  contextId?: string | null;
  contextSnapshot?: unknown;
  status: string;
  dueAt: string;
  reviewedByEmail?: string | null;
  reviewedAt?: string | null;
  resolutionNote?: string | null;
  createdAt: string;
  updatedAt: string;
  reporterUser?: AdminReportUser | null;
  reportedUser?: AdminReportUser | null;
  reviewedByUser?: AdminReportUser | null;
};

export type AdminReportPagination = {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
};
