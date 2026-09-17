"use client";

import { FormEvent, useEffect, useId, useRef, useState } from "react";
import { ImagePlus, Loader2, SendHorizonal, X } from "lucide-react";

import type { MessageReceipt } from "@/lib/chat-receipts-client";

import { IMAGE_SIZE_ERROR, MAX_IMAGE_BYTES } from "@/lib/upload-limits";

export type ChatAttachment = {
  id: string;
  kind: "image";
  url: string;
  mimeType?: string;
  byteSize?: number;
  position?: number;
};

export type ChatMessage = {
  receipt?: MessageReceipt;
  id: string;
  senderUserId: string;
  text: string;
  createdAt: string;
  attachments?: ChatAttachment[];
  senderUser: {
    name: string | null;
    avatarUrl: string | null;
  };
};

type SelectedImage = {
  key: string;
  file: File;
  previewUrl: string;
  assetId?: string;
};

const ACCEPTED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const MAX_ATTACHMENTS = 4;

export function ChatComposer({
  placeholder,
  sendLabel,
  onSend
}: {
  placeholder: string;
  sendLabel?: string;
  onSend: (text: string, attachmentIds: string[]) => Promise<void>;
}) {
  const inputId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const selectedImagesRef = useRef<SelectedImage[]>([]);
  const [text, setText] = useState("");
  const [selectedImages, setSelectedImages] = useState<SelectedImage[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    selectedImagesRef.current = selectedImages;
  }, [selectedImages]);

  useEffect(() => {
    return () => {
      selectedImagesRef.current.forEach((image) => URL.revokeObjectURL(image.previewUrl));
    };
  }, []);

  function addImages(files: FileList | null) {
    if (!files?.length) return;

    const nextFiles = Array.from(files);
    const unsupported = nextFiles.some((file) => !ACCEPTED_IMAGE_TYPES.has(file.type));
    const oversized = nextFiles.some((file) => ACCEPTED_IMAGE_TYPES.has(file.type) && file.size > MAX_IMAGE_BYTES);
    const accepted = nextFiles.filter((file) => ACCEPTED_IMAGE_TYPES.has(file.type) && file.size <= MAX_IMAGE_BYTES);

    setSelectedImages((current) => {
      const availableSlots = MAX_ATTACHMENTS - current.length;
      const added = accepted.slice(0, availableSlots).map((file, index) => ({
        key: `${file.name}-${file.lastModified}-${file.size}-${index}-${crypto.randomUUID()}`,
        file,
        previewUrl: URL.createObjectURL(file)
      }));

      if (unsupported) {
        setError("Можно прикреплять только JPG, PNG, WEBP или GIF.");
      } else if (oversized) {
        setError(IMAGE_SIZE_ERROR);
      } else if (accepted.length > availableSlots) {
        setError(`К сообщению можно прикрепить не больше ${MAX_ATTACHMENTS} фото.`);
      } else {
        setError(null);
      }

      return [...current, ...added];
    });

    if (inputRef.current) {
      inputRef.current.value = "";
    }
  }

  function removeImage(key: string) {
    setSelectedImages((current) => {
      const removed = current.find((image) => image.key === key);
      if (removed) URL.revokeObjectURL(removed.previewUrl);
      return current.filter((image) => image.key !== key);
    });
    setError(null);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (loading || (!text.trim() && selectedImages.length === 0)) return;

    setLoading(true);
    setError(null);

    try {
      const uploaded = await Promise.all(
        selectedImages.map(async (image) => {
          if (image.assetId) return image.assetId;

          const asset = await uploadChatImage(image.file);
          setSelectedImages((current) =>
            current.map((candidate) => (candidate.key === image.key ? { ...candidate, assetId: asset.id } : candidate))
          );
          return asset.id;
        })
      );

      await onSend(text.trim(), uploaded);
      setText("");
      setSelectedImages((current) => {
        current.forEach((image) => URL.revokeObjectURL(image.previewUrl));
        return [];
      });
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось отправить сообщение");
    } finally {
      setLoading(false);
    }
  }

  const canSend = Boolean(text.trim()) || selectedImages.length > 0;

  return (
    <form onSubmit={submit} className="space-y-2">
      {selectedImages.length > 0 ? (
        <div className="grid grid-cols-4 gap-2">
          {selectedImages.map((image) => (
            <div key={image.key} className="group relative aspect-square overflow-hidden rounded-2xl bg-cream">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={image.previewUrl} alt="" className="h-full w-full object-cover" />
              <button
                type="button"
                onClick={() => removeImage(image.key)}
                disabled={loading}
                aria-label={`Убрать фото ${image.file.name}`}
                className="absolute right-1.5 top-1.5 flex h-7 w-7 items-center justify-center rounded-full bg-ink/80 text-white shadow-sm disabled:opacity-50"
              >
                <X className="h-4 w-4" />
              </button>
              {loading && !image.assetId ? (
                <div className="absolute inset-0 flex items-center justify-center bg-ink/40 text-white">
                  <Loader2 className="h-5 w-5 animate-spin" />
                </div>
              ) : null}
            </div>
          ))}
        </div>
      ) : null}

      <div className="flex items-end gap-2">
        <input
          ref={inputRef}
          id={inputId}
          type="file"
          multiple
          accept="image/jpeg,image/png,image/webp,image/gif"
          className="sr-only"
          onChange={(event) => addImages(event.target.files)}
          disabled={loading || selectedImages.length >= MAX_ATTACHMENTS}
        />
        <label
          htmlFor={inputId}
          aria-label="Добавить фото"
          title="Добавить фото"
          className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl border border-ink/10 bg-cream text-ink transition ${
            loading || selectedImages.length >= MAX_ATTACHMENTS ? "pointer-events-none opacity-50" : "cursor-pointer hover:bg-mint"
          }`}
        >
          <ImagePlus className="h-5 w-5" />
        </label>
        <textarea
          rows={2}
          value={text}
          onChange={(event) => setText(event.target.value)}
          className="input min-h-[52px] min-w-0 flex-1 resize-none py-3 text-sm placeholder:text-sm"
          placeholder={placeholder}
          disabled={loading}
        />
        <button
          type="submit"
          disabled={loading || !canSend}
          aria-label={sendLabel ?? "Отправить"}
          className={`flex h-12 shrink-0 items-center justify-center rounded-2xl bg-clay text-white disabled:opacity-50 ${
            sendLabel ? "min-w-[108px] px-4 text-sm font-semibold" : "w-12"
          }`}
        >
          {loading ? <Loader2 className="h-5 w-5 animate-spin" /> : sendLabel ?? <SendHorizonal className="h-5 w-5" />}
        </button>
      </div>
      <div className="px-1 text-xs text-ink/50">До {MAX_ATTACHMENTS} фото · JPG, PNG, WEBP или GIF</div>
      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
    </form>
  );
}

export function ChatMessageAttachments({ attachments = [] }: { attachments?: ChatAttachment[] }) {
  const images = attachments
    .filter((attachment) => attachment.kind === "image" && Boolean(attachment.url))
    .sort((left, right) => (left.position ?? 0) - (right.position ?? 0));
  const [activeImage, setActiveImage] = useState<ChatAttachment | null>(null);

  useEffect(() => {
    if (!activeImage) return;

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setActiveImage(null);
    }

    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [activeImage]);

  if (images.length === 0) return null;

  return (
    <>
      <div className={`grid gap-1.5 ${images.length === 1 ? "grid-cols-1" : "grid-cols-2"}`}>
        {images.map((attachment) => (
          <button
            key={attachment.id}
            type="button"
            onClick={() => setActiveImage(attachment)}
            className="relative aspect-square min-w-0 overflow-hidden rounded-xl bg-black/5 focus:outline-none focus:ring-2 focus:ring-clay"
            aria-label="Открыть фото"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={attachment.url} alt="" loading="lazy" className="h-full w-full object-cover" />
          </button>
        ))}
      </div>
      {activeImage ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Просмотр фото"
          className="fixed inset-0 z-[100] flex items-center justify-center bg-black/85 p-4"
          onClick={() => setActiveImage(null)}
        >
          <button
            type="button"
            onClick={() => setActiveImage(null)}
            aria-label="Закрыть фото"
            className="absolute right-4 top-4 flex h-11 w-11 items-center justify-center rounded-full bg-white/15 text-white"
          >
            <X className="h-6 w-6" />
          </button>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={activeImage.url}
            alt=""
            className="max-h-full max-w-full rounded-xl object-contain"
            onClick={(event) => event.stopPropagation()}
          />
        </div>
      ) : null}
    </>
  );
}

async function uploadChatImage(file: File): Promise<ChatAttachment> {
  const body = new FormData();
  body.append("file", file);

  const response = await fetch("/uploads/chat-media", {
    method: "POST",
    body
  });
  const data = (await response.json()) as { asset?: ChatAttachment; error?: string };

  if (!response.ok || !data.asset) {
    throw new Error(data.error ?? "Не удалось загрузить фото");
  }

  return data.asset;
}
