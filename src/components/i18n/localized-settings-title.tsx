"use client";

import { useLocale } from "@/components/i18n/locale-provider";
import { SectionTitle } from "@/components/ui/section-title";

export function LocalizedSettingsTitle() {
  const { t } = useLocale();

  return (
    <SectionTitle
      eyebrow={t("settings.eyebrow")}
      title={t("settings.title")}
      subtitle={t("settings.subtitle")}
    />
  );
}
