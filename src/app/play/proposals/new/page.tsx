import { redirect } from "next/navigation";
import { type Sport } from "@prisma/client";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { PageShell } from "@/components/layout/page-shell";
import { GameRequestForm } from "@/components/forms/game-request-form";
import { SectionTitle } from "@/components/ui/section-title";
import { getCourtsForUser, getGameRequestDetail, getMatchesForUser } from "@/server/app-data";

export default async function NewProposalPage({
  searchParams
}: {
  searchParams: { matchId?: string; courtId?: string; sport?: string; gameRequestId?: string };
}) {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/play/proposals/new"));
  }

  const editingGameRequest = searchParams.gameRequestId
    ? await getGameRequestDetail(searchParams.gameRequestId, user.id)
    : null;

  if (searchParams.gameRequestId && !editingGameRequest) {
    redirect("/inbox");
  }

  const [matches, courts] = await Promise.all([getMatchesForUser(user.id), getCourtsForUser(user.id)]);
  const availableSports = Array.isArray(user.preferredSports)
    ? user.preferredSports.filter((sport): sport is string => typeof sport === "string")
    : ["tennis"];
  const requestedCourtId = editingGameRequest?.proposedCourtId ?? searchParams.courtId;
  const requestedCourt = requestedCourtId ? courts.find((court) => court.id === requestedCourtId) : null;
  const requestedCourtSports = Array.isArray(requestedCourt?.supportedSports)
    ? requestedCourt.supportedSports.filter((sport): sport is Sport => typeof sport === "string")
    : [];
  const defaultSport =
    editingGameRequest?.sport ??
    (searchParams.sport && availableSports.includes(searchParams.sport)
      ? (searchParams.sport as Sport)
      : requestedCourtSports.find((sport) => availableSports.includes(sport)) ?? undefined);
  const matchOptions = matches.map((match) => ({
    id: match.id,
    otherUserName: match.user1Id === user.id ? match.user2.name ?? "Игрок" : match.user1.name ?? "Игрок"
  }));

  if (editingGameRequest && !matchOptions.some((match) => match.id === editingGameRequest.matchId)) {
    const otherUser = editingGameRequest.match.user1Id === user.id ? editingGameRequest.match.user2 : editingGameRequest.match.user1;
    matchOptions.unshift({
      id: editingGameRequest.matchId,
      otherUserName: otherUser.name ?? "Игрок"
    });
  }

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Предложение"
        title={editingGameRequest ? "Измени условия игры." : "Отправь готовое предложение на игру."}
        subtitle={
          editingGameRequest
            ? "Сохраним изменения в этой же договоренности без создания второй игры."
            : "Один экран: вид спорта, игрок, площадка, время и формат. Комментарий оставляй коротким."
        }
      />
      <GameRequestForm
        availableSports={availableSports as Sport[]}
        matches={matchOptions}
        courts={courts.map((court) => ({
          id: court.id,
          name: court.name,
          address: court.address,
          phone: court.phone,
          district: court.district,
          locationLat: court.locationLat,
          locationLng: court.locationLng,
          supportedSports: Array.isArray(court.supportedSports)
            ? court.supportedSports.filter((sport): sport is Sport => typeof sport === "string")
            : []
        }))}
        defaultMatchId={editingGameRequest?.matchId ?? searchParams.matchId}
        defaultCourtId={editingGameRequest?.proposedCourtId ?? searchParams.courtId}
        defaultSport={defaultSport}
        editingGameRequest={
          editingGameRequest
            ? {
                id: editingGameRequest.id,
                matchId: editingGameRequest.matchId,
                proposedCourtId: editingGameRequest.proposedCourtId,
                proposedDatetime: editingGameRequest.proposedDatetime.toISOString(),
                durationMinutes: editingGameRequest.durationMinutes,
                levelRangeMin: editingGameRequest.levelRangeMin,
                levelRangeMax: editingGameRequest.levelRangeMax,
                sport: editingGameRequest.sport,
                format: editingGameRequest.format,
                comment: editingGameRequest.comment,
                status: editingGameRequest.status
              }
            : null
        }
      />
    </PageShell>
  );
}
