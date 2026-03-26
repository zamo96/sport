import { NextRequest } from "next/server";

import { createDefaultGuestOnboardingDraft } from "@/lib/guest-draft";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { guestDiscoverSchema } from "@/lib/validators";
import { getDiscoverCandidatesForGuestDraft } from "@/server/discover";
import { serializeUserPreview } from "@/server/serializers";

export async function POST(request: NextRequest) {
  try {
    const body = guestDiscoverSchema.parse(await request.json());
    const candidates = await getDiscoverCandidatesForGuestDraft(
      {
        ...createDefaultGuestOnboardingDraft(),
        ...body.draft,
        gender: body.draft.gender ?? null,
        district: body.draft.district ?? null
      },
      body.filters
    );

    return ok({
      users: candidates.map((candidate) => serializeUserPreview(candidate))
    });
  } catch (error) {
    return fail(getErrorMessage(error));
  }
}
