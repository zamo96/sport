"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { promoteGuestDraftAfterSignIn, type SignedInUser } from "@/components/forms/guest-draft-promotion";
import { useLocale } from "@/components/i18n/locale-provider";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { apiFetch } from "@/lib/client-api";
import { clearGuestOnboardingDraft, createDefaultGuestOnboardingDraft, loadGuestOnboardingDraft } from "@/lib/guest-draft";
import { buildLatestUserAgreementPayload } from "@/lib/legal-contract";
import { takePendingVkSignIn } from "@/lib/vk-id-client";

/**
 * Завершение входа через VK ID, начатого в браузере: code_verifier лежит в
 * этой вкладке, код и device_id пришли от VK через /auth/vk/callback.
 */
export function VkCallback() {
  const { t } = useLocale();
  const router = useRouter();
  const searchParams = useSearchParams();
  const [message, setMessage] = useState<string>(t("auth.vk.returning"));
  const [failed, setFailed] = useState(false);
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;

    const code = searchParams.get("code");
    const deviceId = searchParams.get("device_id");
    const state = searchParams.get("state") ?? "";

    const pending = takePendingVkSignIn();
    if (!code || !deviceId || !pending || pending.state !== state) {
      setFailed(true);
      setMessage(t("auth.vk.failed"));
      return;
    }

    (async () => {
      try {
        const draft = loadGuestOnboardingDraft() ?? createDefaultGuestOnboardingDraft();
        const data = await apiFetch<{ user: SignedInUser }>("/auth/vk", {
          method: "POST",
          body: JSON.stringify({
            code,
            deviceId,
            state,
            codeVerifier: pending.codeVerifier,
            showOnMap: draft.showOnMap,
            consentReview: true,
            userAgreement: buildLatestUserAgreementPayload()
          })
        });
        const onboardingCompleted = await promoteGuestDraftAfterSignIn(data.user, draft);
        if (onboardingCompleted) clearGuestOnboardingDraft();
        router.replace(onboardingCompleted ? pending.continueHref : "/onboarding");
        router.refresh();
      } catch (error) {
        setFailed(true);
        setMessage(error instanceof Error ? error.message : t("auth.vk.failed"));
      }
    })();
  }, [router, searchParams, t]);

  return (
    <div className="flex min-h-[60vh] items-center">
      <Panel className="w-full space-y-4 text-center">
        <p className="text-base font-semibold text-ink">{message}</p>
        {failed ? (
          <Button fullWidth onClick={() => router.replace("/auth?step=email")}>
            {t("auth.vk.backToSignIn")}
          </Button>
        ) : null}
      </Panel>
    </div>
  );
}
