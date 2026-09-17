import { describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

import { IMAGE_SIZE_ERROR, MAX_IMAGE_BYTES } from "@/lib/upload-limits";
import { MAX_CHAT_UPLOAD_REQUEST_BYTES, parseChatMediaFiles } from "@/server/chat-media-multipart";

const boundary = "chat-photo-boundary";
const chunk = Buffer.alloc(64 * 1024, 120);
const fileHeader = (index: number) => Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="photo-${index}.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`);

function requestFor(source: Iterable<Uint8Array>) {
  const iterator = source[Symbol.iterator]();
  const cancel = vi.fn();
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      const next = iterator.next();
      if (next.done) controller.close(); else controller.enqueue(next.value);
    },
    cancel
  });
  const request = new NextRequest(new Request("http://localhost/uploads/chat-media", {
    method: "POST", headers: { "content-type": `multipart/form-data; boundary=${boundary}` }, body, duplex: "half"
  } as RequestInit));
  return { request, cancel };
}

function* files(sizes: number[]) {
  for (const [index, size] of sizes.entries()) {
    yield fileHeader(index);
    for (let remaining = size; remaining > 0; remaining -= chunk.length) yield chunk.subarray(0, Math.min(remaining, chunk.length));
    yield Buffer.from("\r\n");
  }
  yield Buffer.from(`--${boundary}--\r\n`);
}

describe("inclusive streaming photo limits", () => {
  it.each([5 * 1024 * 1024 + 1, MAX_IMAGE_BYTES])("accepts %i bytes without Content-Length", async (size) => {
    const { request } = requestFor(files([size]));
    expect(request.headers.get("content-length")).toBeNull();
    const result = await parseChatMediaFiles(request);
    expect(result).toHaveLength(1);
    expect(result[0].size).toBe(size);
    expect(result[0].bytes.length).toBe(size);
  });

  it("rejects the first extra byte and cancels a never-ending upload", async () => {
    let emitted = 0;
    function* endlessFile() {
      yield fileHeader(0);
      while (true) { emitted += chunk.length; yield chunk; }
    }
    const { request, cancel } = requestFor(endlessFile());
    await expect(parseChatMediaFiles(request)).rejects.toThrow(IMAGE_SIZE_ERROR);
    expect(cancel).toHaveBeenCalledTimes(1);
    expect(emitted).toBeLessThanOrEqual(MAX_IMAGE_BYTES + 3 * chunk.length);
  });

  it("rejects exactly one extra file byte", async () => {
    const { request } = requestFor(files([MAX_IMAGE_BYTES + 1]));
    await expect(parseChatMediaFiles(request)).rejects.toThrow(IMAGE_SIZE_ERROR);
  });

  it("retains the four-attachment limit", async () => {
    await expect(parseChatMediaFiles(requestFor(files([1, 1, 1, 1])).request)).resolves.toHaveLength(4);
    await expect(parseChatMediaFiles(requestFor(files([1, 1, 1, 1, 1])).request)).rejects.toThrow("Можно загрузить не больше 4 фото");
  });

  it("bounds the total streamed request even for ignored metadata without Content-Length", async () => {
    let emitted = 0;
    function* endlessField() {
      yield Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n`);
      while (true) { emitted += chunk.length; yield chunk; }
    }
    const { request, cancel } = requestFor(endlessField());
    await expect(parseChatMediaFiles(request)).rejects.toThrow("Общий размер загрузки слишком большой");
    expect(cancel).toHaveBeenCalledTimes(1);
    expect(emitted).toBeLessThanOrEqual(MAX_CHAT_UPLOAD_REQUEST_BYTES + 3 * chunk.length);
  });
});
