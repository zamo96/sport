import { redirect } from "next/navigation";

import { AdminClubEditor } from "@/components/admin/admin-club-editor";
import { getAdminAccessState } from "@/lib/admin";

export const dynamic = "force-dynamic";

export default async function AdminClubDetailPage({ params }: { params: { id: string } }) {
  const access = await getAdminAccessState();
  const continuePath = `/admin/clubs/${params.id}`;
  if (!access.user) redirect(`/auth?continue=${encodeURIComponent(continuePath)}&step=email`);
  if (!access.configured || !access.isAdmin) redirect("/admin");

  return (
    <main className="min-h-screen bg-[#f7f5ef] px-4 py-6 text-ink">
      <div className="mx-auto w-full max-w-7xl">
        <AdminClubEditor clubId={params.id} />
      </div>
    </main>
  );
}
