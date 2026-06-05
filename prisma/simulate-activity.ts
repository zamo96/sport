import { prisma } from "@/lib/prisma";
import { runDemoActivitySimulation } from "./demo-simulator";

async function main() {
  const appendMode = process.argv.includes("--append");
  await runDemoActivitySimulation(prisma, {
    resetExisting: !appendMode
  });
  console.log(`Симуляция активности завершена (${appendMode ? "append" : "reset"} mode)`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
