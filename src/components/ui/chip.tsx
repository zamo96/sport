import { cn } from "@/lib/utils";

export function Chip({
  children,
  active = false,
  onClick,
  className
}: {
  children: React.ReactNode;
  active?: boolean;
  onClick?: () => void;
  className?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "rounded-full border px-3 py-2 text-xs font-semibold transition",
        active
          ? "border-ink bg-ink text-white"
          : "border-white/60 bg-white/80 text-ink/70",
        className
      )}
    >
      {children}
    </button>
  );
}

