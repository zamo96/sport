import Link from "next/link";
import { History } from "lucide-react";
import { redirect } from "next/navigation";

import { AdminPlayerEditor } from "@/components/admin/admin-player-editor";
import { getAdminAccessState } from "@/lib/admin";

export const dynamic = "force-dynamic";

export default async function AdminPlayerDetailPage({ params }: { params: { id: string } }) {
  const access = await getAdminAccessState();
  const continuePath = `/admin/players/${params.id}`;
  if (!access.user) redirect(`/auth?continue=${encodeURIComponent(continuePath)}&step=email`);
  if (!access.configured || !access.isAdmin) redirect("/admin");

  return (
    <main className="min-h-screen bg-[#f7f5ef] px-4 py-6 text-ink">
      <div className="mx-auto w-full max-w-7xl">
        <div className="mb-4 flex justify-end">
          <Link
            href={`/admin/analytics?userId=${encodeURIComponent(params.id)}#journal`}
            className="inline-flex h-11 items-center justify-center gap-2 rounded-lg border border-court/20 bg-white px-4 text-sm font-semibold text-court hover:bg-court/5"
          >
            <History className="h-4 w-4" />
            История действий
          </Link>
        </div>
        <AdminPlayerEditor playerId={params.id} currentAdminId={access.user.id} />
      </div>
    </main>
  );
}
