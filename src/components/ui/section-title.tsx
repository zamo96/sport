export function SectionTitle({
  eyebrow,
  title,
  subtitle
}: {
  eyebrow?: string;
  title: string;
  subtitle?: string;
}) {
  return (
    <div className="mb-4">
      {eyebrow ? (
        <div className="mb-2 text-xs font-semibold uppercase tracking-[0.24em] text-court">
          {eyebrow}
        </div>
      ) : null}
      <h1 className="text-[28px] font-bold leading-none text-ink">{title}</h1>
      {subtitle ? <p className="mt-2 max-w-sm text-sm leading-6 text-ink/70">{subtitle}</p> : null}
    </div>
  );
}

