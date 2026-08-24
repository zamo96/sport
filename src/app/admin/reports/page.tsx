import Link from "next/link";
import { ArrowLeft, ShieldAlert } from "lucide-react";
import { redirect } from "next/navigation";

import { AdminReportList } from "@/components/admin/admin-report-list";
import { getAdminAccessState } from "@/lib/admin";

export default async function AdminReportsPage() {
  const access = await getAdminAccessState();
  if (!access.user) redirect(`/auth?continue=${encodeURIComponent("/admin/reports")}&step=email`);
  if (!access.configured || !access.isAdmin) redirect("/admin");

  return (
    <main className="min-h-screen bg-[#f7f5ef] px-4 py-6 text-ink">
      <div className="mx-auto w-full max-w-6xl space-y-5">
        <header className="rounded-lg border border-black/10 bg-white p-5 shadow-[0_10px_30px_rgba(17,38,29,0.08)]">
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-[0.2em] text-red-700"><ShieldAlert className="h-4 w-4" />Модерация</div>
              <h1 className="mt-2 text-3xl font-bold">Жалобы пользователей</h1>
              <p className="mt-2 text-sm text-ink/60">Решение по каждой жалобе нужно принять не позднее 24 часов.</p>
            </div>
            <Link href="/admin" className="inline-flex h-11 items-center justify-center gap-2 rounded-lg bg-black/5 px-4 text-sm font-semibold"><ArrowLeft className="h-4 w-4" />В админку</Link>
          </div>
        </header>
        <AdminReportList />
      </div>
    </main>
  );
}
