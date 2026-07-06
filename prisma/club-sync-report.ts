import path from "node:path";

import { prisma } from "@/lib/prisma";
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
  const report = await buildClubSyncReport({
    runId: args.get("run-id") ?? args.get("runId"),
    sourceType: args.get("source-type") ?? args.get("sourceType"),
    city: args.get("city"),
    limit: args.get("limit") ? Number(args.get("limit")) : undefined,
    prisma
  });

  if (!report) {
    throw new Error("Club sync report not found");
  }

  if (args.get("format") === "json") {
    console.log(JSON.stringify(report, null, 2));
    return;
  }

  console.log(formatClubSyncReportMarkdown(report));
}

if (process.argv[1] && path.resolve(process.argv[1]).endsWith("club-sync-report.ts")) {
  main()
    .catch((error) => {
      console.error(error);
      process.exit(1);
    })
    .finally(async () => {
      await prisma.$disconnect();
    });
}
