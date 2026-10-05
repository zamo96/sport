import { Suspense } from "react";

import { VkCallback } from "@/components/auth/vk-callback";
import { PageShell } from "@/components/layout/page-shell";

export const dynamic = "force-dynamic";

/** Завершение входа через VK ID, начатого в браузере. */
export default function VkFinishPage() {
  return (
    <PageShell withNav={false}>
      <Suspense fallback={null}>
        <VkCallback />
      </Suspense>
    </PageShell>
  );
}
