import Busboy from "busboy";
import { NextRequest } from "next/server";

import { IMAGE_SIZE_ERROR } from "@/lib/upload-limits";
import { MAX_CHAT_ATTACHMENTS, MAX_CHAT_IMAGE_BYTES } from "@/server/chat-media";

export const MAX_CHAT_UPLOAD_REQUEST_BYTES = MAX_CHAT_ATTACHMENTS * MAX_CHAT_IMAGE_BYTES + 256 * 1024;

export type UploadedChatMediaFile = {
  bytes: Buffer;
  name: string;
  size: number;
  type: string;
};

export async function parseChatMediaFiles(request: NextRequest): Promise<UploadedChatMediaFile[]> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("multipart/form-data")) {
    throw new Error("Ожидается multipart-загрузка");
  }
  if (!request.body) {
    throw new Error("Добавьте фото");
  }

  return new Promise<UploadedChatMediaFile[]>((resolve, reject) => {
    const parser = Busboy({
      headers: Object.fromEntries(request.headers.entries()),
      limits: {
        files: MAX_CHAT_ATTACHMENTS,
        // Busboy emits "limit" at equality. One sentinel byte keeps our
        // public maximum inclusive while still bounding the parser itself.
        fileSize: MAX_CHAT_IMAGE_BYTES + 1,
        parts: MAX_CHAT_ATTACHMENTS + 4
      }
    });
    const reader = request.body!.getReader();
    const files: UploadedChatMediaFile[] = [];
    let settled = false;

    const failOnce = (error: Error) => {
      if (settled) return;
      settled = true;
      reject(error);
      void reader.cancel(error).catch(() => undefined);
      // Avoid destroying Busboy's current file inside its synchronous event
      // handler, but wake a producer waiting for backpressure immediately after.
      queueMicrotask(() => parser.destroy());
    };

    parser.on("file", (fieldName, stream, info) => {
      stream.on("limit", () => failOnce(new Error(IMAGE_SIZE_ERROR)));
      stream.on("error", failOnce);
      if (fieldName !== "file" && fieldName !== "files") {
        stream.resume();
        return;
      }

      const chunks: Buffer[] = [];
      let byteSize = 0;
      stream.on("data", (chunk: Buffer) => {
        if (settled) return;
        byteSize += chunk.length;
        if (byteSize > MAX_CHAT_IMAGE_BYTES) {
          failOnce(new Error(IMAGE_SIZE_ERROR));
          return;
        }
        chunks.push(chunk);
      });
      stream.on("end", () => {
        if (!stream.truncated && !settled) {
          files.push({
            bytes: Buffer.concat(chunks, byteSize),
            name: info.filename || "chat-photo",
            size: byteSize,
            type: info.mimeType
          });
        }
      });
    });
    parser.on("filesLimit", () => failOnce(new Error(`Можно загрузить не больше ${MAX_CHAT_ATTACHMENTS} фото`)));
    parser.on("partsLimit", () => failOnce(new Error("Слишком много частей multipart-запроса")));
    parser.on("error", failOnce);
    parser.on("finish", () => {
      if (!settled) {
        settled = true;
        resolve(files);
      }
    });

    void (async () => {
      let totalBytes = 0;
      try {
        while (!settled) {
          const { done, value } = await reader.read();
          if (done || settled) break;
          totalBytes += value.byteLength;
          if (totalBytes > MAX_CHAT_UPLOAD_REQUEST_BYTES) {
            failOnce(new Error("Общий размер загрузки слишком большой"));
            return;
          }
          if (!parser.write(Buffer.from(value)) && !settled) {
            await new Promise<void>((resume, rejectDrain) => {
              const cleanup = () => {
                parser.off("drain", drained);
                parser.off("close", drained);
                parser.off("error", failed);
              };
              const drained = () => { cleanup(); resume(); };
              const failed = (error: Error) => { cleanup(); rejectDrain(error); };
              parser.once("drain", drained);
              parser.once("close", drained);
              parser.once("error", failed);
              if (settled || parser.destroyed) drained();
            });
          }
        }
        if (!settled) parser.end();
      } catch (error) {
        failOnce(error instanceof Error ? error : new Error("Не удалось прочитать загрузку"));
      } finally {
        reader.releaseLock();
      }
    })();
  });
}
