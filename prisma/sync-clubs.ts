import path from "node:path";

import { prisma } from "@/lib/prisma";
import { runClubSync } from "@/server/club-sync";
import { buildClubSyncReport, formatClubSyncReportMarkdown } from "@/server/club-sync-report";

function parseArgs(argv: string[]) {
  const result = new Map<string, string>();

  for (const arg of argv) {
    const [key, ...rest] = arg.replace(/^--/, "").split("=");
    if (!key || rest.length === 0) {
      continue;
    }
    result.set(key, rest.join("="));
  }

  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const summary = await runClubSync({
    provider: args.get("provider") as "yandex" | "json" | undefined,
    city: args.get("city"),
    sourceType: args.get("source-type"),
    autoPublishNew: args.get("auto-publish-new") === "1" ? true : undefined,
    autoHideStale: args.get("auto-hide-stale") === "1" ? true : undefined,
    staleAfterDays: args.get("stale-after-days") ? Number(args.get("stale-after-days")) : undefined,
    checkWebsites: args.get("check-websites") === "0" ? false : undefined,
    websitesOnly: args.get("websites-only") === "1",
    websiteLimit: args.get("website-limit") ? Number(args.get("website-limit")) : undefined,
    autoApplyWebsiteChanges: args.get("auto-apply-website") === "1" ? true : undefined,
    prisma
  });

  if (args.get("report") === "1" || args.get("include-report") === "1") {
    const report = await buildClubSyncReport({
      runId: summary.runId,
      prisma
    });

    if (args.get("report-format") === "markdown") {
      if (report) {
        console.log(formatClubSyncReportMarkdown(report));
      }
      return;
    }

    console.log(JSON.stringify({ summary, report }, null, 2));
    return;
  }

  console.log(JSON.stringify(summary, null, 2));
}

if (process.argv[1] && path.resolve(process.argv[1]).endsWith("sync-clubs.ts")) {
  main()
    .catch((error) => {
      console.error(error);
      process.exit(1);
    })
    .finally(async () => {
      await prisma.$disconnect();
    });
}
