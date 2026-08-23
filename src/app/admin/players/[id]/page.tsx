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
        <AdminPlayerEditor playerId={params.id} currentAdminId={access.user.id} />
      </div>
    </main>
  );
}
