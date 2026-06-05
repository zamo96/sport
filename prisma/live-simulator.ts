import { prisma } from "@/lib/prisma";
import { runLiveActivityTick } from "./demo-simulator";

async function main() {
  const intervalArg = process.argv.find((arg) => arg.startsWith("--interval="));
  const ticksArg = process.argv.find((arg) => arg.startsWith("--ticks="));
  const intervalMs = Math.max(2000, Number(intervalArg?.split("=")[1] ?? 12000));
  const ticksLimit = Number(ticksArg?.split("=")[1] ?? 0);

  let tick = 0;
  let stopped = false;

  function stop() {
    stopped = true;
  }

  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);

  console.log(`Live-симуляция запущена. Интервал: ${intervalMs} мс${ticksLimit > 0 ? `, тиков: ${ticksLimit}` : ""}`);

  while (!stopped) {
    tick += 1;
    const summary = await runLiveActivityTick(prisma, {
      seed: Date.now() + tick
    });

    console.log(
      `[tick ${tick}] users=${summary.users}, likes/dislikes=${summary.swipes}, matches=${summary.matches}, searches=${summary.searches}, responses=${summary.responses}, messages=${summary.messages}, requests=${summary.gameRequests}`
    );

    if (ticksLimit > 0 && tick >= ticksLimit) {
      break;
    }

    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  console.log("Live-симуляция остановлена.");
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
