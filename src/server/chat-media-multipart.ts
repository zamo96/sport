import Busboy from "busboy";
import { NextRequest } from "next/server";

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
        fileSize: MAX_CHAT_IMAGE_BYTES,
        parts: MAX_CHAT_ATTACHMENTS + 4
      }
    });
    const files: UploadedChatMediaFile[] = [];
    let settled = false;

    const failOnce = (error: Error) => {
      if (settled) return;
      settled = true;
      reject(error);
    };

    parser.on("file", (fieldName, stream, info) => {
      if (fieldName !== "file" && fieldName !== "files") {
        stream.resume();
        return;
      }

      const chunks: Buffer[] = [];
      let byteSize = 0;
      stream.on("data", (chunk: Buffer) => {
        byteSize += chunk.length;
        chunks.push(chunk);
      });
      stream.on("limit", () => failOnce(new Error("Фото должно быть не больше 5 МБ")));
      stream.on("error", failOnce);
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
      const reader = request.body!.getReader();
      let totalBytes = 0;
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          totalBytes += value.byteLength;
          if (totalBytes > MAX_CHAT_UPLOAD_REQUEST_BYTES) {
            await reader.cancel();
            failOnce(new Error("Общий размер загрузки слишком большой"));
            parser.destroy();
            return;
          }
          if (!parser.write(Buffer.from(value))) {
            await new Promise<void>((resume) => parser.once("drain", resume));
          }
        }
        parser.end();
      } catch (error) {
        failOnce(error instanceof Error ? error : new Error("Не удалось прочитать загрузку"));
        parser.destroy();
      }
    })();
  });
}
