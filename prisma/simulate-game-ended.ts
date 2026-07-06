import { GameRequestStatus } from "@prisma/client";

import { prisma } from "@/lib/prisma";
import { buildCompletedGameSimulationDatetime } from "@/server/game-reports";

type CliOptions = {
  id?: string;
  latest: boolean;
  list: boolean;
  allowProduction: boolean;
};

function parseOptions(): CliOptions {
  const args = process.argv.slice(2);
  const options = new Map(
    args
      .filter((arg) => arg.startsWith("--"))
      .map((arg) => {
        const [key, value = "true"] = arg.slice(2).split("=");
        return [key, value] as const;
      })
  );
  const positionalId = args.find((arg) => !arg.startsWith("--"));

  return {
    id: options.get("id") ?? positionalId,
    latest: options.get("latest") === "true",
    list: options.get("list") === "true",
    allowProduction: options.get("allow-production") === "true"
  };
}

function assertSimulationAllowed(options: CliOptions) {
  if (process.env.NODE_ENV === "production" && !options.allowProduction) {
    throw new Error("Refusing to mutate production data. Pass --allow-production only if this is intentional.");
  }
}

async function printAcceptedGames() {
  const games = await prisma.gameRequest.findMany({
    where: {
      status: GameRequestStatus.accepted
    },
    include: {
      createdByUser: true,
      matchedUser: true,
      proposedCourt: true
    },
    orderBy: {
      proposedDatetime: "asc"
    },
    take: 20
  });

  if (games.length === 0) {
    console.log("Нет подтверждённых игр для симуляции.");
    return;
  }

  console.log("Подтверждённые игры:");
  for (const game of games) {
    console.log(
      [
        `- ${game.id}`,
        game.proposedDatetime.toISOString(),
        `${game.createdByUser.name ?? game.createdByUser.email} vs ${game.matchedUser.name ?? game.matchedUser.email}`,
        game.proposedCourt?.name ?? "Место уточняется"
      ].join(" · ")
    );
  }
}

async function resolveGameRequestId(options: CliOptions) {
  if (options.id) {
    return options.id;
  }

  if (!options.latest) {
    throw new Error("Укажи id игры: npm run simulate:game-ended -- <gameRequestId> или используй --latest.");
  }

  const latestGame = await prisma.gameRequest.findFirst({
    where: {
      status: GameRequestStatus.accepted
    },
    orderBy: {
      proposedDatetime: "asc"
    },
    select: {
      id: true
    }
  });

  if (!latestGame) {
    throw new Error("Не нашёл подтверждённую игру для --latest.");
  }

  return latestGame.id;
}

async function main() {
  const options = parseOptions();
  assertSimulationAllowed(options);

  if (options.list) {
    await printAcceptedGames();
    return;
  }

  const gameRequestId = await resolveGameRequestId(options);
  const gameRequest = await prisma.gameRequest.findUnique({
    where: {
      id: gameRequestId
    },
    include: {
      createdByUser: true,
      matchedUser: true,
      proposedCourt: true,
      report: true
    }
  });

  if (!gameRequest) {
    throw new Error(`Игра ${gameRequestId} не найдена.`);
  }

  if (gameRequest.status !== GameRequestStatus.accepted) {
    throw new Error(`Игра ${gameRequest.id} должна быть accepted, текущий статус: ${gameRequest.status}.`);
  }

  const rootRequestId = gameRequest.sharedRootId ?? gameRequest.id;
  const relatedRequests = await prisma.gameRequest.findMany({
    where: {
      OR: [{ id: rootRequestId }, { sharedRootId: rootRequestId }],
      status: GameRequestStatus.accepted
    },
    select: {
      id: true
    }
  });
  const requestIds = relatedRequests.length > 0 ? relatedRequests.map((request) => request.id) : [gameRequest.id];
  const simulatedDatetime = buildCompletedGameSimulationDatetime(gameRequest.durationMinutes);

  await prisma.$transaction(async (tx) => {
    await tx.gameRequest.updateMany({
      where: {
        id: {
          in: requestIds
        }
      },
      data: {
        proposedDatetime: simulatedDatetime,
        outcome: null,
        outcomeUpdatedAt: null
      }
    });

    await tx.chatMessage.create({
      data: {
        matchId: gameRequest.matchId,
        gameRequestId: gameRequest.id,
        senderUserId: gameRequest.createdByUserId,
        text: "Симуляция: игра перенесена в прошлое, теперь можно проверить фотоотчёт."
      }
    });

    await tx.match.update({
      where: {
        id: gameRequest.matchId
      },
      data: {
        updatedAt: new Date()
      }
    });
  });

  console.log("Игра переведена в завершённое состояние.");
  console.log(`GameRequest: ${gameRequest.id}`);
  console.log(`Затронутые заявки: ${requestIds.join(", ")}`);
  console.log(`Новое время начала: ${simulatedDatetime.toISOString()}`);
  console.log(`Игроки: ${gameRequest.createdByUser.name ?? gameRequest.createdByUser.email} vs ${gameRequest.matchedUser.name ?? gameRequest.matchedUser.email}`);
  console.log(`Корт: ${gameRequest.proposedCourt?.name ?? "Место уточняется"}`);
  console.log(`Открой: /play/games/${gameRequest.id}`);

  if (gameRequest.report) {
    console.log("У этой игры уже есть фотоотчёт; форма создания нового отчёта не появится.");
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
