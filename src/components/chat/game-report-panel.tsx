"use client";

import { ChangeEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Camera,
  CheckCircle2,
  Clock3,
  Image as ImageIcon,
  Loader2,
  Upload,
  XCircle
} from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { IMAGE_SIZE_ERROR, MAX_IMAGE_BYTES, MAX_IMAGE_MEGABYTES } from "@/lib/upload-limits";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

type GameReportVisibility = "profile" | "participants" | "private";
type GameReportConfirmationStatus = "pending" | "confirmed" | "disputed";
type GameReportStatus = "pending" | "confirmed" | "disputed";

type GameReportPanelProps = {
  canSimulateEndedGame: boolean;
  gameRequest: {
    id: string;
    status: "pending" | "accepted" | "declined" | "canceled";
    outcome?: "played" | "not_played" | null;
    proposedDatetime: string;
    durationMinutes?: number | null;
    proposedCourt: {
      name: string;
      address: string;
    } | null;
    report?: GameReportPayload | null;
  };
};

type GameReportPayload = {
  id: string;
  createdByUserId: string;
  comment: string | null;
  visibility: GameReportVisibility;
  status: GameReportStatus;
  createdAt: string | Date;
  updatedAt?: string | Date;
  createdByUser?: {
    name?: string | null;
  } | null;
  photos: Array<{
    id: string;
    url: string;
    position: number;
  }>;
  confirmations: Array<{
    id: string;
    userId: string;
    status: GameReportConfirmationStatus;
    user?: {
      name?: string | null;
    } | null;
  }>;
};

type UploadPhotoResponse = {
  photoUrl: string;
};

const VISIBILITY_OPTIONS: Array<{
  value: GameReportVisibility;
  title: string;
  description: string;
}> = [
  { value: "profile", title: "В профиле", description: "Видно в игровой ленте" },
  { value: "participants", title: "Участникам", description: "Только игрокам этой игры" },
  { value: "private", title: "Приватно", description: "Без публикации в профиле" }
];

export function GameReportPanel({
  canSimulateEndedGame,
  gameRequest
}: GameReportPanelProps) {
  const router = useRouter();
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [comment, setComment] = useState("");
  const [visibility, setVisibility] = useState<GameReportVisibility>("profile");
  const [loadingAction, setLoadingAction] = useState<"submit" | "simulate" | null>(null);
  const [error, setError] = useState<string | null>(null);

  const hasEnded = hasGameRequestEnded(gameRequest.proposedDatetime, gameRequest.durationMinutes);
  const isAccepted = gameRequest.status === "accepted";
  const canCreateReport = isAccepted && hasEnded && !gameRequest.report && gameRequest.outcome !== "not_played";
  const canSimulate = canSimulateEndedGame && isAccepted && !hasEnded;

  useEffect(() => {
    const urls = selectedFiles.map((file) => URL.createObjectURL(file));
    setPreviews(urls);

    return () => {
      urls.forEach((url) => URL.revokeObjectURL(url));
    };
  }, [selectedFiles]);

  function handleFilesChange(event: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.currentTarget.files ?? []).slice(0, 5);
    event.currentTarget.value = "";
    if (files.some((file) => file.size > MAX_IMAGE_BYTES)) {
      setError(IMAGE_SIZE_ERROR);
      return;
    }
    setSelectedFiles(files);
    setError(null);
  }

  async function submitReport() {
    if (selectedFiles.length === 0 || loadingAction) {
      return;
    }

    setLoadingAction("submit");
    setError(null);

    try {
      const photoUrls: string[] = [];

      for (const file of selectedFiles) {
        const formData = new FormData();
        formData.append("file", file);

        const uploadResponse = await fetch(`/uploads/game-reports/${gameRequest.id}`, {
          method: "POST",
          body: formData
        });
        const uploadData = (await uploadResponse.json()) as Partial<UploadPhotoResponse> & { error?: string };

        if (!uploadResponse.ok || !uploadData.photoUrl) {
          throw new Error(uploadData.error ?? "Не удалось загрузить фото");
        }

        photoUrls.push(uploadData.photoUrl);
      }

      await apiFetch(`/game-requests/${gameRequest.id}/report`, {
        method: "POST",
        body: JSON.stringify({
          photoUrls,
          comment,
          visibility
        })
      });

      setSelectedFiles([]);
      setComment("");
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось отправить фотоотчёт");
    } finally {
      setLoadingAction(null);
    }
  }

  async function simulateEndedGame() {
    if (!canSimulate || loadingAction) {
      return;
    }

    setLoadingAction("simulate");
    setError(null);

    try {
      await apiFetch(`/game-requests/${gameRequest.id}/simulate-ended`, {
        method: "POST",
        body: JSON.stringify({})
      });
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось завершить игру в симуляции");
    } finally {
      setLoadingAction(null);
    }
  }

  return (
    <Panel className="space-y-4 bg-white/90">
      <div className="flex items-start gap-3">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-mint text-court">
          <Camera className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="text-xs font-semibold uppercase tracking-[0.18em] text-court">Фотоотчёт</div>
          <h2 className="mt-1 text-lg font-bold text-ink">Итог после игры</h2>
          <p className="mt-1 text-sm leading-6 text-ink/65">
            После завершения подтверждённой игры можно добавить 1-5 фото и короткий комментарий.
          </p>
        </div>
      </div>

      {gameRequest.report ? (
        <ReportSummary report={gameRequest.report} />
      ) : canCreateReport ? (
        <div className="space-y-4">
          <div className="rounded-2xl bg-mint/45 px-4 py-3 text-sm leading-6 text-ink/75">
            Игра завершилась. Если вы сыграли, загрузи фотоотчёт: он отметит игру как состоявшуюся и сохранит результат в истории.
          </div>

          <div className="space-y-3">
            <label className="block">
              <span className="mb-2 block text-sm font-semibold text-ink">Фото</span>
              <input
                type="file"
                accept="image/*"
                multiple
                className="hidden"
                onChange={handleFilesChange}
                disabled={loadingAction === "submit"}
              />
              <span className="flex min-h-24 cursor-pointer flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-court/35 bg-mint/25 px-4 py-5 text-center text-sm font-semibold text-court transition hover:bg-mint/40">
                <Upload className="h-5 w-5" />
                Выбрать фото
                <span className="text-xs font-medium text-ink/50">JPG, PNG, WEBP или GIF · до {MAX_IMAGE_MEGABYTES} МБ</span>
              </span>
            </label>

            {previews.length > 0 ? (
              <div className="grid grid-cols-5 gap-2">
                {previews.map((preview, index) => (
                  <div
                    key={preview}
                    className="aspect-square rounded-2xl bg-cover bg-center ring-1 ring-white"
                    style={{ backgroundImage: `url("${preview}")` }}
                    aria-label={`Фото ${index + 1}`}
                  />
                ))}
              </div>
            ) : null}
          </div>

          <label className="block space-y-2">
            <span className="text-sm font-semibold text-ink">Комментарий</span>
            <textarea
              value={comment}
              onChange={(event) => setComment(event.target.value.slice(0, 240))}
              className="min-h-24 w-full resize-none rounded-2xl border border-white bg-white/80 px-4 py-3 text-sm text-ink outline-none ring-court/20 transition placeholder:text-ink/35 focus:ring-4"
              placeholder="Хорошая игра, спасибо за матч!"
              disabled={loadingAction === "submit"}
            />
          </label>

          <div className="space-y-2">
            <div className="text-sm font-semibold text-ink">Кто видит отчёт</div>
            <div className="grid gap-2 sm:grid-cols-3">
              {VISIBILITY_OPTIONS.map((option) => {
                const selected = visibility === option.value;
                return (
                  <button
                    key={option.value}
                    type="button"
                    className={`min-h-20 rounded-2xl px-3 py-3 text-left transition ${
                      selected ? "bg-ink text-white" : "bg-white/80 text-ink"
                    }`}
                    onClick={() => setVisibility(option.value)}
                    disabled={loadingAction === "submit"}
                  >
                    <span className="block text-sm font-bold">{option.title}</span>
                    <span className={`mt-1 block text-xs leading-5 ${selected ? "text-white/70" : "text-ink/55"}`}>
                      {option.description}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          <Button fullWidth onClick={submitReport} disabled={selectedFiles.length === 0 || loadingAction === "submit"}>
            {loadingAction === "submit" ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <ImageIcon className="mr-2 h-4 w-4" />}
            Отправить фотоотчёт
          </Button>
        </div>
      ) : (
        <ReportAvailabilityState
          status={gameRequest.status}
          outcome={gameRequest.outcome}
          hasEnded={hasEnded}
          canSimulate={canSimulate}
          isSimulating={loadingAction === "simulate"}
          onSimulate={simulateEndedGame}
        />
      )}

      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">{error}</div> : null}
    </Panel>
  );
}

function ReportSummary({
  report
}: {
  report: GameReportPayload;
}) {
  const status = getReportStatus(report.status);

  return (
    <div className="space-y-4">
      <div className={`rounded-2xl px-4 py-3 text-sm leading-6 ${status.className}`}>
        <div className="flex items-center gap-2 font-bold">
          {status.icon}
          {status.label}
        </div>
        <div className="mt-1 opacity-80">
          {report.createdByUser?.name ? `${report.createdByUser.name} добавил(а) отчёт` : "Фотоотчёт добавлен"} ·{" "}
          {new Date(report.createdAt).toLocaleString("ru-RU")}
        </div>
      </div>

      {report.photos.length > 0 ? (
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
          {report.photos.map((photo, index) => (
            <a
              key={photo.id}
              href={photo.url}
              target="_blank"
              rel="noreferrer"
              className="aspect-square rounded-2xl bg-stone-100 bg-cover bg-center ring-1 ring-white"
              style={{ backgroundImage: `url("${photo.url}")` }}
              aria-label={`Открыть фото ${index + 1}`}
            />
          ))}
        </div>
      ) : null}

      {report.comment ? (
        <div className="rounded-2xl bg-white/80 px-4 py-3 text-sm leading-6 text-ink/72">{report.comment}</div>
      ) : null}

      <div className="rounded-2xl bg-white/70 px-4 py-3 text-sm text-ink/60">
        Отчёт сохранён без дополнительного подтверждения.
      </div>
    </div>
  );
}

function ReportAvailabilityState({
  status,
  outcome,
  hasEnded,
  canSimulate,
  isSimulating,
  onSimulate
}: {
  status: "pending" | "accepted" | "declined" | "canceled";
  outcome?: "played" | "not_played" | null;
  hasEnded: boolean;
  canSimulate: boolean;
  isSimulating: boolean;
  onSimulate: () => void;
}) {
  if (outcome === "not_played") {
    return (
      <div className="rounded-2xl bg-stone-100 px-4 py-3 text-sm leading-6 text-ink/65">
        Игра отмечена как несостоявшаяся, поэтому фотоотчёт недоступен.
      </div>
    );
  }

  if (status !== "accepted") {
    return (
      <div className="rounded-2xl bg-stone-100 px-4 py-3 text-sm leading-6 text-ink/65">
        Фотоотчёт появится после подтверждения и завершения игры.
      </div>
    );
  }

  if (!hasEnded) {
    return (
      <div className="space-y-3">
        <div className="rounded-2xl bg-stone-100 px-4 py-3 text-sm leading-6 text-ink/65">
          Игра ещё не закончилась по расписанию. Фотоотчёт станет доступен после окончания.
        </div>
        {canSimulate ? (
          <Button fullWidth variant="ghost" onClick={onSimulate} disabled={isSimulating}>
            {isSimulating ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Clock3 className="mr-2 h-4 w-4" />}
            Симулировать завершение игры
          </Button>
        ) : null}
      </div>
    );
  }

  return (
    <div className="rounded-2xl bg-mint/35 px-4 py-3 text-sm leading-6 text-ink/65">
      Можно добавить фотоотчёт, если игра состоялась.
    </div>
  );
}

function hasGameRequestEnded(proposedDatetime: string, durationMinutes?: number | null) {
  const duration = durationMinutes ?? 90;
  const finishedAt = new Date(proposedDatetime).getTime() + duration * 60 * 1000;
  return Date.now() >= finishedAt;
}

function getReportStatus(status: GameReportStatus) {
  switch (status) {
    case "confirmed":
      return {
        label: "Фотоотчёт сохранён",
        className: "bg-emerald-50 text-emerald-800",
        icon: <CheckCircle2 className="h-4 w-4" />
      };
    case "disputed":
      return {
        label: "Фотоотчёт спорный",
        className: "bg-red-50 text-red-700",
        icon: <XCircle className="h-4 w-4" />
      };
    case "pending":
    default:
      return {
        label: "Фотоотчёт сохранён",
        className: "bg-mint/35 text-court",
        icon: <Clock3 className="h-3.5 w-3.5" />
      };
  }
}
