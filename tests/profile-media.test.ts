import { describe, expect, it } from "vitest";

import { normalizeProfileMediaList, removeProfileMedia } from "@/lib/profile-media";
import { retryPrismaWriteConflict } from "@/lib/prisma-transaction";

const state = {
  avatarUrl: "https://cdn.test/primary.jpg",
  profilePhotoUrls: [
    "https://cdn.test/primary.jpg",
    "https://cdn.test/secondary.jpg",
    "https://cdn.test/third.jpg"
  ],
  profileVideoUrls: ["https://cdn.test/intro.mp4"]
};

describe("profile media removal", () => {
  it("removes a non-primary photo without changing the avatar", () => {
    expect(removeProfileMedia(state, "https://cdn.test/secondary.jpg")).toMatchObject({
      mediaType: "photo",
      removed: true,
      avatarUrl: "https://cdn.test/primary.jpg",
      profilePhotoUrls: ["https://cdn.test/primary.jpg", "https://cdn.test/third.jpg"],
      profileVideoUrls: ["https://cdn.test/intro.mp4"]
    });
  });

  it("promotes the next photo when removing the primary photo", () => {
    expect(removeProfileMedia(state, "https://cdn.test/primary.jpg")).toMatchObject({
      removed: true,
      avatarUrl: "https://cdn.test/secondary.jpg",
      profilePhotoUrls: ["https://cdn.test/secondary.jpg", "https://cdn.test/third.jpg"]
    });
  });

  it("clears the avatar when removing the last photo", () => {
    expect(
      removeProfileMedia(
        {
          avatarUrl: "https://cdn.test/only.jpg",
          profilePhotoUrls: ["https://cdn.test/only.jpg"],
          profileVideoUrls: []
        },
        "https://cdn.test/only.jpg"
      )
    ).toMatchObject({ removed: true, avatarUrl: null, profilePhotoUrls: [] });
  });

  it("removes a video without changing photos or the avatar", () => {
    expect(removeProfileMedia(state, "https://cdn.test/intro.mp4")).toMatchObject({
      mediaType: "video",
      removed: true,
      avatarUrl: state.avatarUrl,
      profilePhotoUrls: state.profilePhotoUrls,
      profileVideoUrls: []
    });
  });

  it("is idempotent for a repeated or unknown URL and does not change the avatar", () => {
    const unknown = removeProfileMedia(state, "https://other.test/not-owned.jpg");

    expect(unknown).toMatchObject({
      mediaType: "photo",
      removed: false,
      avatarUrl: state.avatarUrl,
      profilePhotoUrls: state.profilePhotoUrls,
      profileVideoUrls: state.profileVideoUrls
    });
    expect(removeProfileMedia(unknown, "https://other.test/not-owned.jpg")).toEqual(unknown);
  });

  it("normalizes stored lists before applying ownership checks", () => {
    expect(normalizeProfileMediaList([" photo.jpg ", "photo.jpg", null, ""], 6)).toEqual(["photo.jpg"]);
  });
});

describe("profile media transaction retries", () => {
  it("retries P2034 write conflicts and returns the successful result", async () => {
    let attempts = 0;

    await expect(
      retryPrismaWriteConflict(async () => {
        attempts += 1;
        if (attempts < 3) {
          throw Object.assign(new Error("write conflict"), { code: "P2034" });
        }
        return "saved";
      }, 3)
    ).resolves.toBe("saved");
    expect(attempts).toBe(3);
  });

  it("does not retry other errors", async () => {
    let attempts = 0;
    const failure = Object.assign(new Error("connection failed"), { code: "P1001" });

    await expect(
      retryPrismaWriteConflict(async () => {
        attempts += 1;
        throw failure;
      }, 3)
    ).rejects.toBe(failure);
    expect(attempts).toBe(1);
  });
});
