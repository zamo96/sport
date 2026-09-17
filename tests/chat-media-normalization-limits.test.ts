import { beforeEach, describe, expect, it, vi } from "vitest";

import { MAX_IMAGE_BYTES, NORMALIZED_IMAGE_SIZE_ERROR } from "@/lib/upload-limits";
import { MAX_CHAT_IMAGE_PIXELS, normalizeChatImage } from "@/server/chat-media";

const processor = vi.hoisted(() => ({ metadata: vi.fn(), rotate: vi.fn(), jpeg: vi.fn(), toBuffer: vi.fn() }));
vi.mock("sharp", () => ({ default: vi.fn(() => processor) }));
const jpegHeader = Buffer.from([0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9]);

beforeEach(() => {
  vi.clearAllMocks();
  processor.metadata.mockResolvedValue({ width: 2, height: 2 });
  processor.rotate.mockReturnValue(processor);
  processor.jpeg.mockReturnValue(processor);
});

describe("normalized chat image limits", () => {
  it("accepts an output exactly at the photo limit", async () => {
    const output = Buffer.alloc(MAX_IMAGE_BYTES);
    processor.toBuffer.mockResolvedValue(output);
    const normalized = await normalizeChatImage(jpegHeader);
    expect(normalized.bytes).toBe(output);
  });

  it("preserves the useful 20 MiB error if normalization expands the file past the limit", async () => {
    processor.toBuffer.mockResolvedValue(Buffer.alloc(MAX_IMAGE_BYTES + 1));
    await expect(normalizeChatImage(jpegHeader)).rejects.toThrow(NORMALIZED_IMAGE_SIZE_ERROR);
  });

  it("still rejects oversized pixel counts and broken decoding", async () => {
    expect(MAX_CHAT_IMAGE_PIXELS).toBe(40_000_000);
    processor.metadata.mockResolvedValueOnce({ width: 10_000, height: 4_001 });
    await expect(normalizeChatImage(jpegHeader)).rejects.toThrow("Слишком большое разрешение фото");
    processor.metadata.mockRejectedValueOnce(new Error("decoder failure"));
    await expect(normalizeChatImage(jpegHeader)).rejects.toThrow("Не удалось безопасно обработать фото");
  });
});
