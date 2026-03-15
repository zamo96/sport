import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

export function Panel({
  children,
  className
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("rounded-[28px] border border-white/60 bg-white/85 p-4 shadow-card", className)}>
      {children}
    </section>
  );
}

