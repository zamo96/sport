"use client";

import { useMemo, useState } from "react";
import { Building2, Check, MapPin, Search, TrainFront } from "lucide-react";

import { getDistrictLabel } from "@/lib/constants";
import { buildCourtSearchTerms, matchesSearchTerms, normalizeSearchText } from "@/lib/search-text";

export type CourtSmartPickerOption = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  nearestMetroName?: string | null;
};

type CourtSmartPickerProps = {
  courts: CourtSmartPickerOption[];
  selectedCourtId: string;
  onSelect: (courtId: string) => void;
  placeholder?: string;
  emptyLabel?: string;
  emptyDescription?: string;
  maxInitialItems?: number;
};

export function CourtSmartPicker({
  courts,
  selectedCourtId,
  onSelect,
  placeholder = "Найти клуб, метро или район",
  emptyLabel = "Без привязки",
  emptyDescription = "Оставить без конкретного клуба",
  maxInitialItems = 18
}: CourtSmartPickerProps) {
  const [query, setQuery] = useState("");

  const filteredCourts = useMemo(() => {
    const normalizedQuery = normalizeSearchText(query);
    const sortedCourts = [...courts].sort((left, right) => {
      if (left.id === selectedCourtId) return -1;
      if (right.id === selectedCourtId) return 1;
      return left.name.localeCompare(right.name, "ru", { sensitivity: "base" });
    });

    if (!normalizedQuery) {
      return sortedCourts.slice(0, maxInitialItems);
    }

    return sortedCourts.filter((court) =>
      matchesSearchTerms(
        buildCourtSearchTerms({
          name: court.name,
          address: court.address,
          district: court.district,
          nearestMetroName: court.nearestMetroName,
          sports: []
        }),
        normalizedQuery
      )
    );
  }, [courts, maxInitialItems, query, selectedCourtId]);

  const hiddenCount = Math.max(courts.length - filteredCourts.length, 0);

  return (
    <div className="space-y-3">
      <label className="relative block">
        <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/35" />
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          className="input pl-11"
          placeholder={placeholder}
        />
      </label>

      {!query.trim() && courts.length > maxInitialItems ? (
        <div className="text-xs text-ink/55">
          Показали первые {maxInitialItems} вариантов. Начни вводить название клуба, метро или район.
        </div>
      ) : null}

      {query.trim() && hiddenCount > 0 ? (
        <div className="text-xs text-ink/55">
          Нашли {filteredCourts.length} вариантов по запросу.
        </div>
      ) : null}

      <div className="max-h-[440px] min-h-[360px] space-y-2 overflow-y-auto pr-1">
        <CourtSmartPickerRow
          title={emptyLabel}
          metaItems={[{ icon: "mappin", text: emptyDescription }]}
          selected={!selectedCourtId}
          onClick={() => onSelect("")}
        />

        {filteredCourts.length === 0 ? (
          <div className="rounded-[22px] border border-dashed border-line px-4 py-4 text-sm text-ink/58">
            Ничего не найдено. Попробуй название клуба, метро или район.
          </div>
        ) : (
          filteredCourts.map((court) => (
            <CourtSmartPickerRow
              key={court.id}
              title={court.name}
              metaItems={[
                court.nearestMetroName ? { icon: "metro", text: court.nearestMetroName } : null,
                getDistrictLabel(court.district) ? { icon: "district", text: getDistrictLabel(court.district) ?? "" } : null,
                court.address ? { icon: "address", text: court.address } : null
              ].filter((item): item is { icon: "metro" | "district" | "address" | "mappin"; text: string } => Boolean(item))}
              selected={selectedCourtId === court.id}
              onClick={() => onSelect(court.id)}
            />
          ))
        )}
      </div>
    </div>
  );
}

function CourtSmartPickerRow({
  title,
  metaItems,
  selected,
  onClick
}: {
  title: string;
  metaItems: Array<{ icon: "metro" | "district" | "address" | "mappin"; text: string }>;
  selected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`w-full rounded-[22px] border px-4 py-3 text-left transition ${
        selected ? "border-court/30 bg-mint" : "border-line bg-white/85 hover:border-court/20 hover:bg-cream"
      }`}
    >
      <div className="flex items-start gap-3">
        <div className="rounded-2xl bg-cream p-2 text-court">
          <Building2 className="h-4 w-4" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="text-sm font-semibold text-ink">{title}</div>
          <div className="mt-2 space-y-1.5">
            {metaItems.map((item) => (
              <div key={`${item.icon}-${item.text}`} className="flex items-start gap-2 text-xs text-ink/62">
                {item.icon === "metro" ? <TrainFront className="mt-0.5 h-3.5 w-3.5 shrink-0 text-court" /> : null}
                {item.icon === "district" ? <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-court" /> : null}
                {item.icon === "address" ? <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-court" /> : null}
                {item.icon === "mappin" ? <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-court" /> : null}
                <span>{item.text}</span>
              </div>
            ))}
          </div>
        </div>
        {selected ? <Check className="mt-1 h-4 w-4 shrink-0 text-court" /> : null}
      </div>
    </button>
  );
}
