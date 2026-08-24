import { redirect } from "next/navigation";

import { AdminReportEditor } from "@/components/admin/admin-report-editor";
import { getAdminAccessState } from "@/lib/admin";

export default async function AdminReportPage({ params }: { params: { id: string } }) {
  const path = `/admin/reports/${params.id}`;
  const access = await getAdminAccessState();
  if (!access.user) redirect(`/auth?continue=${encodeURIComponent(path)}&step=email`);
  if (!access.configured || !access.isAdmin) redirect("/admin");
  return <main className="min-h-screen bg-[#f7f5ef] px-4 py-6 text-ink"><div className="mx-auto w-full max-w-5xl"><AdminReportEditor reportId={params.id} /></div></main>;
}
