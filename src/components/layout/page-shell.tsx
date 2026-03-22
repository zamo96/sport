import type { ReactNode } from "react";

export function PageShell({
  children,
  withNav = true
}: {
  children: ReactNode;
  withNav?: boolean;
}) {
  return (
    <main
      className={`mx-auto min-h-screen w-full max-w-md bg-court bg-court bg-[length:100%_100%] px-4 ${
        withNav ? "pb-28 pt-5" : "pb-5 pt-3"
      }`}
    >
      <div className={withNav ? "pb-6" : ""}>{children}</div>
    </main>
  );
}
