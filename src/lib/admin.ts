import type { User } from "@prisma/client";

import { getSessionUser } from "@/lib/auth";

export type AdminAccessState = {
  configured: boolean;
  user: User | null;
  isAdmin: boolean;
};

function parseAdminEmailList(value: string | undefined) {
  return value
    ?.split(/[,\s;]+/)
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean) ?? [];
}

export function getConfiguredAdminEmails() {
  return Array.from(
    new Set([
      ...parseAdminEmailList(process.env.ADMIN_EMAILS),
      ...parseAdminEmailList(process.env.ADMIN_EMAIL)
    ])
  );
}

export function isAdminUser(user: Pick<User, "email"> | null | undefined) {
  if (!user?.email) {
    return false;
  }

  return getConfiguredAdminEmails().includes(user.email.trim().toLowerCase());
}

export async function getAdminAccessState(): Promise<AdminAccessState> {
  const user = await getSessionUser();
  const configured = getConfiguredAdminEmails().length > 0;

  return {
    configured,
    user,
    isAdmin: configured && isAdminUser(user)
  };
}

export async function requireAdminUser() {
  const access = await getAdminAccessState();

  if (!access.configured) {
    throw new Error("ADMIN_UNCONFIGURED");
  }

  if (!access.user) {
    throw new Error("UNAUTHORIZED");
  }

  if (!access.isAdmin) {
    throw new Error("FORBIDDEN");
  }

  return access.user;
}
