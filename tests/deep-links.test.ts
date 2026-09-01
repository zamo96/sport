import { describe, expect, it } from "vitest";

import { GET as getRootAasa } from "@/app/apple-app-site-association/route";
import { GET as getWellKnownAasa } from "@/app/.well-known/apple-app-site-association/route";
import {
  APPLE_APP_SITE_ASSOCIATION,
  APP_STORE_URL,
  IOS_APP_ID,
  UNIVERSAL_LINK_PATHS,
  isIPhoneOrIPadUserAgent,
  isPreviewOrCrawlerUserAgent,
  isSupportedDeepLinkPath,
  shouldRedirectDeepLinkToAppStore
} from "@/lib/deep-links";

const IPHONE_SAFARI_UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1";
const IPAD_SAFARI_UA =
  "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1";
const IPADOS_DESKTOP_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1";
const MAC_SAFARI_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15";
const ANDROID_CHROME_UA =
  "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/128.0 Mobile Safari/537.36";

describe("Apple App Site Association", () => {
  it("contains only the approved app and universal-link paths", () => {
    expect(IOS_APP_ID).toBe("M2ZZ39HQZ5.shop.sportsearch.app");
    expect(UNIVERSAL_LINK_PATHS).toEqual(["/users/*", "/play/searches/invite/*"]);
    expect(APPLE_APP_SITE_ASSOCIATION).toEqual({
      applinks: {
        apps: [],
        details: [
          {
            appID: "M2ZZ39HQZ5.shop.sportsearch.app",
            paths: ["/users/*", "/play/searches/invite/*"]
          }
        ]
      }
    });
  });

  it.each([getWellKnownAasa, getRootAasa])("serves JSON without authentication", async (getAasa) => {
    const response = getAasa();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("application/json");
    await expect(response.json()).resolves.toEqual(APPLE_APP_SITE_ASSOCIATION);
  });
});

describe("deep-link App Store fallback", () => {
  it.each([IPHONE_SAFARI_UA, IPAD_SAFARI_UA, IPADOS_DESKTOP_UA])(
    "recognizes an iPhone or iPad browser",
    (userAgent) => {
      expect(isIPhoneOrIPadUserAgent(userAgent)).toBe(true);
    }
  );

  it.each([MAC_SAFARI_UA, ANDROID_CHROME_UA, null, ""])("does not classify other clients as iOS", (userAgent) => {
    expect(isIPhoneOrIPadUserAgent(userAgent)).toBe(false);
  });

  it.each([
    "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
    "Twitterbot/1.0",
    "TelegramBot (like TwitterBot)",
    `${IPHONE_SAFARI_UA} Googlebot/2.1`
  ])("keeps previews and crawlers on the web", (userAgent) => {
    expect(isPreviewOrCrawlerUserAgent(userAgent)).toBe(true);
    expect(isIPhoneOrIPadUserAgent(userAgent)).toBe(false);
  });

  it.each([
    "/users/player-1",
    "/users/player-1/",
    "/users/player-1?source=share",
    "/play/searches/invite/search-1",
    "/play/searches/invite/search-1#details"
  ])("accepts a supported deep link: %s", (pathname) => {
    expect(isSupportedDeepLinkPath(pathname)).toBe(true);
  });

  it.each([
    "/users",
    "/users/player-1/report",
    "/play/searches/search-1",
    "/play/searches/invite",
    "/discover"
  ])("rejects a non-universal-link path: %s", (pathname) => {
    expect(isSupportedDeepLinkPath(pathname)).toBe(false);
  });

  it("redirects only supported iPhone/iPad requests to the configured App Store page", () => {
    expect(APP_STORE_URL).toBe("https://apps.apple.com/app/id6768862885");
    expect(
      shouldRedirectDeepLinkToAppStore({ pathname: "/users/player-1", userAgent: IPHONE_SAFARI_UA })
    ).toBe(true);
    expect(
      shouldRedirectDeepLinkToAppStore({ pathname: "/play/searches/invite/search-1", userAgent: IPAD_SAFARI_UA })
    ).toBe(true);
    expect(shouldRedirectDeepLinkToAppStore({ pathname: "/discover", userAgent: IPHONE_SAFARI_UA })).toBe(false);
    expect(
      shouldRedirectDeepLinkToAppStore({ pathname: "/users/player-1", userAgent: ANDROID_CHROME_UA })
    ).toBe(false);
  });
});
