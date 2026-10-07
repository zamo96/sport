import { afterEach, describe, expect, it, vi } from "vitest";
import { appLatestVersion, appMinSupportedVersion } from "@/lib/app-version";
import * as versionRoute from "@/app/app/version/route";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("app version", () => {
  it("reads the versions from the env", () => {
    vi.stubEnv("APP_LATEST_VERSION", "1.3.0");
    vi.stubEnv("APP_MIN_SUPPORTED_VERSION", " 1.2.2 ");
    expect(appLatestVersion()).toBe("1.3.0");
    expect(appMinSupportedVersion()).toBe("1.2.2");
  });

  it("falls back to the defaults when the env is empty or malformed", () => {
    vi.stubEnv("APP_LATEST_VERSION", "");
    vi.stubEnv("APP_MIN_SUPPORTED_VERSION", "v1.2");
    expect(appLatestVersion()).toBe("1.2.2");
    expect(appMinSupportedVersion()).toBe("1.0.0");
  });

  it("answers at request time, so an env change needs only a restart", async () => {
    expect(versionRoute.dynamic).toBe("force-dynamic");
    vi.stubEnv("APP_LATEST_VERSION", "1.2.3");
    const response = await versionRoute.GET();
    expect(await response.json()).toEqual({ latestVersion: "1.2.3", minVersion: "1.0.0" });
  });
});
