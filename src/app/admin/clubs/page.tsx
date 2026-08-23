import Link from "next/link";
import { redirect } from "next/navigation";
import { Building2, ChevronLeft, ShieldCheck } from "lucide-react";
import type { Sport } from "@prisma/client";

import { AdminClubList } from "@/components/admin/admin-club-list";
import type { AdminClubStatus } from "@/components/admin/club-types";
import { getAdminAccessState } from "@/lib/admin";
import { SPORT_OPTIONS } from "@/lib/constants";

export const dynamic = "force-dynamic";

export default async function AdminClubsPage({
  searchParams
}: {
  searchParams?: Record<string, string | string[] | undefined>;
}) {
  const access = await getAdminAccessState();
  if (!access.user) redirect(`/auth?continue=${encodeURIComponent("/admin/clubs")}&step=email`);
  if (!access.configured || !access.isAdmin) redirect("/admin");

  const rawStatus = first(searchParams?.status);
  const statuses: AdminClubStatus[] = ["active", "needs_review", "hidden", "archived"];
  const status = statuses.includes(rawStatus as AdminClubStatus) ? rawStatus as AdminClubStatus : "all";
  const rawSport = first(searchParams?.sport);
  const sport = SPORT_OPTIONS.includes(rawSport as Sport) ? rawSport as Sport : "all";
  const rawPage = Number(first(searchParams?.page) ?? "1");

  return (
    <main className="min-h-screen bg-[#f7f5ef] px-4 py-6 text-ink">
      <div className="mx-auto w-full max-w-7xl space-y-5">
        <header className="rounded-lg border border-black/10 bg-white px-5 py-4 shadow-[0_10px_30px_rgba(17,38,29,0.08)]">
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.22em] text-court">
                <ShieldCheck className="h-4 w-4" /> Модерация
              </div>
              <h1 className="mt-2 flex items-center gap-2 text-2xl font-bold md:text-3xl">
                <Building2 className="h-7 w-7 text-court" /> Спортивные клубы
              </h1>
              <p className="mt-2 text-sm leading-6 text-ink/65">Проверка, редактирование и управление видимостью клубов.</p>
            </div>
            <Link href="/admin" className="inline-flex h-11 items-center justify-center gap-2 rounded-lg bg-black/5 px-4 text-sm font-semibold text-ink">
              <ChevronLeft className="h-4 w-4" /> В админ-панель
            </Link>
          </div>
        </header>

        <AdminClubList
          initialQuery={first(searchParams?.q) ?? ""}
          initialStatus={status}
          initialCity={first(searchParams?.city) ?? "all"}
          initialSport={sport}
          initialSourceType={first(searchParams?.sourceType) ?? "all"}
          initialPage={Number.isInteger(rawPage) && rawPage > 0 ? rawPage : 1}
        />
      </div>
    </main>
  );
}

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}
