const DEFAULT_SCREENSHOT_TIMEOUT_MS = 15_000;
const DEFAULT_SCREENSHOT_WIDTH = 1365;
const DEFAULT_SCREENSHOT_HEIGHT = 1800;

type ScreenshotStatus = "disabled" | "captured" | "failed";

export type ClubWebsiteScreenshotResult = {
  status: ScreenshotStatus;
  dataUrl: string | null;
  errorMessage: string | null;
};

type DynamicImport = (specifier: string) => Promise<unknown>;

type PlaywrightModule = {
  chromium: {
    launch(options: {
      headless: true;
      executablePath?: string;
      args?: string[];
    }): Promise<PlaywrightBrowser>;
  };
};

type PlaywrightBrowser = {
  newPage(options: {
    viewport: {
      width: number;
      height: number;
    };
  }): Promise<PlaywrightPage>;
  close(): Promise<void>;
};

type PlaywrightPage = {
  goto(url: string, options: {
    waitUntil: "domcontentloaded";
    timeout: number;
  }): Promise<unknown>;
  screenshot(options: {
    type: "jpeg";
    quality: number;
    fullPage: false;
  }): Promise<Buffer>;
};

export function isClubWebsiteScreenshotEnabled() {
  return process.env.CLUB_SYNC_ANALYST_INCLUDE_SCREENSHOT === "1";
}

export async function captureClubWebsiteScreenshotDataUrl(url: string): Promise<ClubWebsiteScreenshotResult> {
  if (!isClubWebsiteScreenshotEnabled()) {
    return {
      status: "disabled",
      dataUrl: null,
      errorMessage: null
    };
  }

  let browser: PlaywrightBrowser | null = null;

  try {
    const playwright = await importPlaywright();
    const timeout = parsePositiveInt(process.env.CLUB_SYNC_SCREENSHOT_TIMEOUT_MS) ?? DEFAULT_SCREENSHOT_TIMEOUT_MS;
    browser = await playwright.chromium.launch({
      headless: true,
      executablePath: process.env.CLUB_SYNC_SCREENSHOT_BROWSER_PATH?.trim() || undefined,
      args: ["--no-sandbox", "--disable-setuid-sandbox"]
    });
    const page = await browser.newPage({
      viewport: {
        width: parsePositiveInt(process.env.CLUB_SYNC_SCREENSHOT_WIDTH) ?? DEFAULT_SCREENSHOT_WIDTH,
        height: parsePositiveInt(process.env.CLUB_SYNC_SCREENSHOT_HEIGHT) ?? DEFAULT_SCREENSHOT_HEIGHT
      }
    });

    await page.goto(url, {
      waitUntil: "domcontentloaded",
      timeout
    });

    const buffer = await page.screenshot({
      type: "jpeg",
      quality: 72,
      fullPage: false
    });

    return {
      status: "captured",
      dataUrl: `data:image/jpeg;base64,${buffer.toString("base64")}`,
      errorMessage: null
    };
  } catch (error) {
    return {
      status: "failed",
      dataUrl: null,
      errorMessage: error instanceof Error ? error.message : String(error)
    };
  } finally {
    await browser?.close().catch(() => undefined);
  }
}

async function importPlaywright() {
  const dynamicImport = new Function("specifier", "return import(specifier)") as DynamicImport;
  const packageNames = [
    process.env.CLUB_SYNC_SCREENSHOT_PLAYWRIGHT_PACKAGE?.trim(),
    "playwright",
    "playwright-core"
  ].filter((value): value is string => Boolean(value));
  let lastError: unknown = null;

  for (const packageName of packageNames) {
    try {
      const playwrightModule = await dynamicImport(packageName);
      if (isPlaywrightModule(playwrightModule)) {
        return playwrightModule;
      }
      lastError = new Error(`${packageName} does not expose chromium`);
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError instanceof Error ? lastError : new Error("playwright module does not expose chromium");
}

function isPlaywrightModule(value: unknown): value is PlaywrightModule {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const chromium = (value as Record<string, unknown>).chromium;
  return Boolean(chromium && typeof chromium === "object" && "launch" in chromium);
}

function parsePositiveInt(value: string | undefined) {
  if (!value) {
    return null;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}
