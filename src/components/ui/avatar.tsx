import Image from "next/image";
import { User2 } from "lucide-react";

import { cn } from "@/lib/utils";

export function Avatar({
  src,
  alt,
  size = "md",
  className
}: {
  src?: string | null;
  alt: string;
  size?: "sm" | "md" | "lg" | "xl";
  className?: string;
}) {
  const sizes = {
    sm: { className: "h-10 w-10", pixels: 40 },
    md: { className: "h-14 w-14", pixels: 56 },
    lg: { className: "h-20 w-20", pixels: 80 },
    xl: { className: "h-28 w-28", pixels: 112 }
  };
  const fallbackLetter = alt.trim().charAt(0).toUpperCase();

  if (src) {
    return (
      <Image
        src={src}
        alt={alt}
        width={sizes[size].pixels}
        height={sizes[size].pixels}
        className={cn("rounded-[28px] object-cover shadow-card", sizes[size].className, className)}
      />
    );
  }

  return (
    <div
      className={cn(
        "flex items-center justify-center rounded-[28px] bg-mint text-ink shadow-card",
        sizes[size].className,
        className
      )}
    >
      {fallbackLetter ? (
        <span className="text-lg font-bold uppercase tracking-[0.08em]">{fallbackLetter}</span>
      ) : (
        <User2 className="h-7 w-7" />
      )}
    </div>
  );
}
