export const IOS_TEAM_ID = "M2ZZ39HQZ5";
export const IOS_BUNDLE_ID = "shop.sportsearch.app";
export const IOS_APP_ID = `${IOS_TEAM_ID}.${IOS_BUNDLE_ID}`;
export const APP_STORE_URL = "https://apps.apple.com/app/id6768862885";

export const UNIVERSAL_LINK_PATHS = ["/users/*", "/play/searches/invite/*"] as const;

export const APPLE_APP_SITE_ASSOCIATION = {
  applinks: {
    apps: [],
    details: [
      {
        appID: IOS_APP_ID,
        paths: [...UNIVERSAL_LINK_PATHS]
      }
    ]
  }
} as const;

const SUPPORTED_DEEP_LINK_PATTERNS = [
  /^\/users\/[^/?#]+\/?$/,
  /^\/play\/searches\/invite\/[^/?#]+\/?$/
] as const;

const PREVIEW_OR_CRAWLER_PATTERN =
  /bot|crawler|spider|slurp|facebookexternalhit|facebot|twitterbot|telegrambot|whatsapp|slackbot|discordbot|linkedinbot|pinterest|vkshare|headlesschrome|lighthouse/i;

export function isSupportedDeepLinkPath(path: string): boolean {
  const pathname = path.split(/[?#]/, 1)[0];
  return SUPPORTED_DEEP_LINK_PATTERNS.some((pattern) => pattern.test(pathname));
}

export function isPreviewOrCrawlerUserAgent(userAgent: string | null | undefined): boolean {
  return Boolean(userAgent && PREVIEW_OR_CRAWLER_PATTERN.test(userAgent));
}

export function isIPhoneOrIPadUserAgent(userAgent: string | null | undefined): boolean {
  if (!userAgent || isPreviewOrCrawlerUserAgent(userAgent)) {
    return false;
  }

  if (/\b(?:iPhone|iPad)\b/i.test(userAgent)) {
    return true;
  }

  // Since iPadOS 13, Safari can identify an iPad as macOS. The Mobile token
  // distinguishes that UA from desktop Safari.
  return /\bMacintosh\b/i.test(userAgent) && /\bMobile\//i.test(userAgent);
}

export function shouldRedirectDeepLinkToAppStore({
  pathname,
  userAgent
}: {
  pathname: string;
  userAgent: string | null | undefined;
}): boolean {
  return isSupportedDeepLinkPath(pathname) && isIPhoneOrIPadUserAgent(userAgent);
}

export function createAppleAppSiteAssociationResponse(): Response {
  return Response.json(APPLE_APP_SITE_ASSOCIATION, {
    headers: {
      "Cache-Control": "public, max-age=3600",
      "Content-Type": "application/json"
    }
  });
}
