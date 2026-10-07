// The in-app update banner follows latestVersion; the forced-update screen follows
// minVersion, raised only when older clients must update. Both come from the runtime
// env, so a new App Store release needs an env change and an app restart, not a new
// image: APP_LATEST_VERSION and APP_MIN_SUPPORTED_VERSION in .env.production.
const DEFAULT_LATEST_VERSION = "1.2.2";
const DEFAULT_MIN_SUPPORTED_VERSION = "1.0.0";
const VERSION_PATTERN = /^\d+(\.\d+){0,2}$/;

/** A typo must not reach the clients: a broken minVersion would lock everyone out. */
function versionFromEnv(value: string | undefined, fallback: string) {
  const trimmed = value?.trim();
  return trimmed && VERSION_PATTERN.test(trimmed) ? trimmed : fallback;
}

export function appLatestVersion() {
  return versionFromEnv(process.env.APP_LATEST_VERSION, DEFAULT_LATEST_VERSION);
}

export function appMinSupportedVersion() {
  return versionFromEnv(process.env.APP_MIN_SUPPORTED_VERSION, DEFAULT_MIN_SUPPORTED_VERSION);
}
