import { describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import sharp from "sharp";

import {
  chatMessagePreview,
  claimChatMessageAttachments,
  detectChatImage,
  normalizeChatImage,
  serializeChatMessage
} from "@/server/chat-media";
import { createGameSearchMessageSchema, messageSchema } from "@/lib/validators";
import { parseChatMediaFiles } from "@/server/chat-media-multipart";

describe("chat media validation", () => {
  it("detects supported images from magic bytes instead of the filename", () => {
    expect(detectChatImage(Buffer.from([0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9])).mimeType).toBe("image/jpeg");
    expect(
      detectChatImage(
        Buffer.concat([
          Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
          Buffer.alloc(4),
          Buffer.from("IEND"),
          Buffer.alloc(4)
        ])
      ).mimeType
    ).toBe("image/png");
    expect(detectChatImage(Buffer.concat([Buffer.from("GIF89a"), Buffer.from([0x3b])])).mimeType).toBe("image/gif");
    expect(
      detectChatImage(Buffer.concat([Buffer.from("RIFF"), Buffer.from([0x04, 0x00, 0x00, 0x00]), Buffer.from("WEBP")])).mimeType
    ).toBe("image/webp");
  });

  it("rejects unsupported content and images larger than 5 MB", () => {
    expect(() => detectChatImage(Buffer.from("not-an-image"))).toThrow(
      "Поддерживаются только JPG, PNG, WEBP или GIF"
    );
    expect(() => detectChatImage(Buffer.alloc(5 * 1024 * 1024 + 1))).toThrow(
      "Фото должно быть не больше 5 МБ"
    );
  });

  it("decodes and re-encodes real images while rejecting header-only payloads", async () => {
    const source = await sharp({
      create: {
        width: 2,
        height: 2,
        channels: 3,
        background: "#2d6a4f"
      }
    })
      .png()
      .toBuffer();

    const normalized = await normalizeChatImage(source);
    expect(normalized.image.mimeType).toBe("image/png");
    await expect(sharp(normalized.bytes).metadata()).resolves.toMatchObject({ width: 2, height: 2 });

    await expect(
      normalizeChatImage(Buffer.from([0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9]))
    ).rejects.toThrow("Не удалось безопасно обработать фото");
  });
});

describe("chat message attachment contract", () => {
  it("requires text or at least one attachment and caps attachments at four", () => {
    expect(messageSchema.safeParse({}).success).toBe(false);
    expect(messageSchema.safeParse({ text: "Привет" }).success).toBe(true);
    expect(messageSchema.safeParse({ attachmentIds: ["asset-1"] }).success).toBe(true);
    expect(
      createGameSearchMessageSchema.safeParse({
        attachmentIds: ["1", "2", "3", "4", "5"]
      }).success
    ).toBe(false);
    expect(messageSchema.safeParse({ attachmentIds: ["1", "1"] }).success).toBe(false);
  });

  it("serializes ordered private URLs and provides photo-only previews", () => {
    const message = serializeChatMessage({
      id: "message-1",
      text: "",
      createdAt: new Date("2026-07-19T12:00:00.000Z"),
      attachments: [
        {
          position: 0,
          asset: {
            id: "asset-1",
            mimeType: "image/jpeg",
            byteSize: 42
          }
        }
      ]
    });

    expect(message.attachments).toEqual([
      {
        id: "asset-1",
        kind: "image",
        url: "/chat-media/asset-1",
        mimeType: "image/jpeg",
        byteSize: 42,
        position: 0
      }
    ]);
    expect(message.createdAt).toBe("2026-07-19T12:00:00.000Z");
    expect(chatMessagePreview(message)).toBe("📷 Фото");
  });

  it("claims every attachment before creating ordered join rows", async () => {
    const updateMany = vi.fn().mockResolvedValue({ count: 2 });
    const createMany = vi.fn().mockResolvedValue({ count: 2 });
    const tx = {
      chatMediaAsset: { updateMany },
      chatMessageMedia: { createMany }
    };

    await claimChatMessageAttachments(tx as never, {
      attachmentIds: ["asset-1", "asset-2"],
      uploaderUserId: "user-1",
      chatMessageId: "message-1"
    });

    expect(updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          uploaderUserId: "user-1",
          claimedAt: null
        })
      })
    );
    expect(createMany).toHaveBeenCalledWith({
      data: [
        { chatMessageId: "message-1", assetId: "asset-1", position: 0 },
        { chatMessageId: "message-1", assetId: "asset-2", position: 1 }
      ]
    });
  });

  it("aborts when any attachment is foreign, missing, or already claimed", async () => {
    const createMany = vi.fn();
    const tx = {
      chatMediaAsset: {
        updateMany: vi.fn().mockResolvedValue({ count: 1 })
      },
      chatMessageMedia: { createMany }
    };

    await expect(
      claimChatMessageAttachments(tx as never, {
        attachmentIds: ["asset-1", "asset-2"],
        uploaderUserId: "user-1",
        chatMessageId: "message-1"
      })
    ).rejects.toThrow("Одно или несколько вложений недоступны");
    expect(createMany).not.toHaveBeenCalled();
  });
});

describe("chat media multipart limits", () => {
  it("stops an oversized streamed file even without Content-Length", async () => {
    const boundary = "chat-media-test";
    const prefix = Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="large.jpg"\r\n` +
        "Content-Type: image/jpeg\r\n\r\n"
    );
    const payload = Buffer.concat([
      prefix,
      Buffer.alloc(5 * 1024 * 1024 + 1),
      Buffer.from(`\r\n--${boundary}--\r\n`)
    ]);
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(payload);
        controller.close();
      }
    });
    const streamedRequest = new Request("http://localhost/uploads/chat-media", {
      method: "POST",
      headers: {
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      body,
      duplex: "half"
    } as unknown as RequestInit);
    const request = new NextRequest(streamedRequest);

    await expect(parseChatMediaFiles(request)).rejects.toThrow("Фото должно быть не больше 5 МБ");
  });
});
