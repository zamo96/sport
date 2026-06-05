import { randomUUID } from "crypto";

import { Gender, PlayFormat, Sport, Surface, SwipeAction } from "@prisma/client";

import { DEFAULT_CITY, SESSION_COOKIE, SESSION_TTL_DAYS, type DistrictOption } from "@/lib/constants";
import { prisma } from "@/lib/prisma";

type CliOptions = {
  baseUrl: string;
  agents: number;
  ticks: number;
  intervalMs: number;
  reset: boolean;
  allowRemote: boolean;
};

type SyntheticAgent = {
  index: number;
  userId: string;
  email: string;
  name: string;
  token: string;
  gender: Gender;
  district: DistrictOption;
  sports: Sport[];
  level: number;
  days: string[];
  timeRanges: string[];
};

type Metric = {
  name: string;
  count: number;
  failed: number;
  totalMs: number;
};

const EMAIL_PREFIX = "synthetic+agent-";
const EMAIL_DOMAIN = "tennissearch.local";

const PERSONAS: Array<Omit<SyntheticAgent, "index" | "userId" | "email" | "token">> = [
  {
    name: "Synthetic Anna",
    gender: Gender.female,
    district: "primorsky",
    sports: [Sport.tennis, Sport.padel],
    level: 6,
    days: ["monday", "wednesday", "saturday"],
    timeRanges: ["evening"]
  },
  {
    name: "Synthetic Ivan",
    gender: Gender.male,
    district: "petrogradsky",
    sports: [Sport.tennis],
    level: 5,
    days: ["tuesday", "thursday", "sunday"],
    timeRanges: ["evening", "day"]
  },
  {
    name: "Synthetic Maria",
    gender: Gender.female,
    district: "central",
    sports: [Sport.badminton, Sport.tennis],
    level: 4,
    days: ["monday", "friday"],
    timeRanges: ["day", "evening"]
  },
  {
    name: "Synthetic Pavel",
    gender: Gender.male,
    district: "moskovsky",
    sports: [Sport.padel, Sport.squash],
    level: 7,
    days: ["wednesday", "friday", "saturday"],
    timeRanges: ["morning", "day"]
  },
  {
    name: "Synthetic Lena",
    gender: Gender.female,
    district: "vasileostrovsky",
    sports: [Sport.tennis, Sport.yoga],
    level: 3,
    days: ["tuesday", "saturday"],
    timeRanges: ["morning", "evening"]
  },
  {
    name: "Synthetic Kirill",
    gender: Gender.male,
    district: "vyborgsky",
    sports: [Sport.tennis, Sport.table_tennis],
    level: 8,
    days: ["thursday", "sunday"],
    timeRanges: ["day"]
  }
];

const metrics = new Map<string, Metric>();

function parseOptions(): CliOptions {
  const args = new Map(
    process.argv
      .slice(2)
      .filter((arg) => arg.startsWith("--"))
      .map((arg) => {
        const [key, value = "true"] = arg.slice(2).split("=");
        return [key, value] as const;
      })
  );

  return {
    baseUrl: args.get("base-url") ?? "http://127.0.0.1:3002",
    agents: Math.max(2, Number(args.get("agents") ?? 8)),
    ticks: Math.max(1, Number(args.get("ticks") ?? 5)),
    intervalMs: Math.max(0, Number(args.get("interval") ?? 1000)),
    reset: args.get("reset") !== "false",
    allowRemote: args.get("allow-remote") === "true" || process.env.SYNTHETIC_AGENT_ALLOW_REMOTE === "1"
  };
}

function assertSafeTarget(options: CliOptions) {
  const url = new URL(options.baseUrl);
  const localHosts = new Set(["localhost", "127.0.0.1", "::1"]);

  if (!localHosts.has(url.hostname) && !options.allowRemote) {
    throw new Error("Remote synthetic simulation requires --allow-remote=true or SYNTHETIC_AGENT_ALLOW_REMOTE=1.");
  }
}

function sessionExpiresAt() {
  return new Date(Date.now() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
}

function pickPersona(index: number) {
  return PERSONAS[(index - 1) % PERSONAS.length];
}

function buildSportLevels(sports: Sport[], level: number) {
  return Object.fromEntries(sports.map((sport, offset) => [sport, Math.max(1, Math.min(10, level + (offset % 2))) ]));
}

function buildAvailability(days: string[], timeRanges: string[]) {
  return Object.fromEntries(days.map((day) => [day, timeRanges]));
}

async function resetSyntheticUsers() {
  await prisma.user.deleteMany({
    where: {
      email: {
        startsWith: EMAIL_PREFIX,
        endsWith: EMAIL_DOMAIN
      }
    }
  });
}

async function createAgents(count: number): Promise<SyntheticAgent[]> {
  const agents: SyntheticAgent[] = [];

  for (let index = 1; index <= count; index += 1) {
    const persona = pickPersona(index);
    const email = `${EMAIL_PREFIX}${String(index).padStart(3, "0")}@${EMAIL_DOMAIN}`;
    const sportLevels = buildSportLevels(persona.sports, persona.level);
    const availabilityByDay = buildAvailability(persona.days, persona.timeRanges);
    const user = await prisma.user.upsert({
      where: { email },
      update: {
        name: persona.name,
        gender: persona.gender,
        city: DEFAULT_CITY,
        district: persona.district,
        preferredDistricts: [persona.district],
        tennisLevel: persona.level,
        preferredSports: persona.sports,
        sportLevels,
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.any,
        bio: "Synthetic user for staging and pre-production journeys.",
        searchRadiusKm: 25,
        availableDays: persona.days,
        availableTimeRanges: persona.timeRanges,
        availabilityByDay,
        availableTimeSlots: persona.days.flatMap((day) => persona.timeRanges.map((range) => `${day}-${range}`)),
        isLookingForGame: true,
        isVerified: true,
        onboardingCompleted: true,
        notificationMatches: false,
        notificationMessages: false,
        notificationGames: false,
        notificationSound: false,
        lastActiveAt: new Date()
      },
      create: {
        email,
        name: persona.name,
        gender: persona.gender,
        city: DEFAULT_CITY,
        district: persona.district,
        preferredDistricts: [persona.district],
        tennisLevel: persona.level,
        preferredSports: persona.sports,
        sportLevels,
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.any,
        bio: "Synthetic user for staging and pre-production journeys.",
        searchRadiusKm: 25,
        availableDays: persona.days,
        availableTimeRanges: persona.timeRanges,
        availabilityByDay,
        availableTimeSlots: persona.days.flatMap((day) => persona.timeRanges.map((range) => `${day}-${range}`)),
        isLookingForGame: true,
        isVerified: true,
        onboardingCompleted: true,
        notificationMatches: false,
        notificationMessages: false,
        notificationGames: false,
        notificationSound: false,
        lastActiveAt: new Date()
      }
    });

    await prisma.session.deleteMany({ where: { userId: user.id } });
    const token = randomUUID();
    await prisma.session.create({
      data: {
        userId: user.id,
        token,
        expiresAt: sessionExpiresAt()
      }
    });

    agents.push({
      index,
      userId: user.id,
      email,
      token,
      ...persona
    });
  }

  return agents;
}

async function apiFetch<T>(baseUrl: string, agent: SyntheticAgent, metricName: string, path: string, init: RequestInit = {}) {
  const startedAt = Date.now();
  const headers = new Headers(init.headers);
  headers.set("cookie", `${SESSION_COOKIE}=${agent.token}`);

  if (init.body && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  try {
    const response = await fetch(new URL(path, baseUrl), {
      ...init,
      headers
    });
    const text = await response.text();
    const payload = text ? JSON.parse(text) : null;

    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}: ${text}`);
    }

    recordMetric(metricName, Date.now() - startedAt, false);
    return payload as T;
  } catch (error) {
    recordMetric(metricName, Date.now() - startedAt, true);
    throw error;
  }
}

function recordMetric(name: string, durationMs: number, failed: boolean) {
  const existing = metrics.get(name) ?? { name, count: 0, failed: 0, totalMs: 0 };
  existing.count += 1;
  existing.failed += failed ? 1 : 0;
  existing.totalMs += durationMs;
  metrics.set(name, existing);
}

async function refreshProfile(baseUrl: string, agent: SyntheticAgent) {
  await apiFetch(baseUrl, agent, "GET /me", "/me");
  await apiFetch(baseUrl, agent, "PATCH /me", "/me", {
    method: "PATCH",
    body: JSON.stringify({
      name: agent.name,
      age: 24 + (agent.index % 20),
      gender: agent.gender,
      city: DEFAULT_CITY,
      district: agent.district,
      preferredDistricts: [agent.district],
      tennisLevel: agent.level,
      preferredSports: agent.sports,
      sportLevels: buildSportLevels(agent.sports, agent.level),
      preferredPlayFormat: PlayFormat.singles,
      preferredSurface: Surface.any,
      bio: "Synthetic user for staging and pre-production journeys.",
      searchRadiusKm: 25,
      availableDays: agent.days,
      availableTimeRanges: agent.timeRanges,
      availabilityByDay: buildAvailability(agent.days, agent.timeRanges),
      isLookingForGame: true,
      notificationMatches: false,
      notificationMessages: false,
      notificationGames: false,
      notificationSound: false
    })
  });
}

async function discoverAndSwipe(baseUrl: string, agent: SyntheticAgent, tick: number) {
  const primarySport = agent.sports[0];
  const payload = await apiFetch<{ users?: Array<{ id: string }> }>(
    baseUrl,
    agent,
    "GET /users/discover",
    `/users/discover?view=swipe&sport=${primarySport}`
  );
  const target = payload.users?.find((user) => user.id !== agent.userId);

  if (!target) {
    return;
  }

  await apiFetch(baseUrl, agent, "POST /swipes", "/swipes", {
    method: "POST",
    body: JSON.stringify({
      toUserId: target.id,
      action: tick % 5 === 0 ? SwipeAction.dislike : SwipeAction.like
    })
  });
}

async function createSearch(baseUrl: string, agent: SyntheticAgent, tick: number) {
  if ((tick + agent.index) % 3 !== 0) {
    return;
  }

  const primarySport = agent.sports[0];
  await apiFetch(baseUrl, agent, "POST /game-searches", "/game-searches", {
    method: "POST",
    body: JSON.stringify({
      preferredDistricts: [agent.district],
      preferredDays: agent.days.slice(0, 2),
      preferredTimeRanges: agent.timeRanges,
      searchType: "regular",
      sport: primarySport,
      desiredLevelMin: Math.max(1, agent.level - 1),
      desiredLevelMax: Math.min(10, agent.level + 1),
      format: PlayFormat.singles,
      playersNeeded: 1,
      comment: `Synthetic regular search tick ${tick}.`
    })
  });
}

async function respondToSearch(baseUrl: string, agent: SyntheticAgent) {
  const search = await prisma.gameSearch.findFirst({
    where: {
      createdByUserId: {
        not: agent.userId
      },
      isActive: true,
      status: {
        in: ["active", "in_review"]
      },
      sport: {
        in: agent.sports
      },
      responses: {
        none: {
          responderUserId: agent.userId
        }
      }
    },
    orderBy: {
      createdAt: "desc"
    },
    select: {
      id: true
    }
  });

  if (!search) {
    return;
  }

  await apiFetch(baseUrl, agent, "POST /game-searches/:id/respond", `/game-searches/${search.id}/respond`, {
    method: "POST",
    body: JSON.stringify({
      message: "Synthetic response: готов присоединиться, если слот еще актуален."
    })
  });
}

async function readOwnSearches(baseUrl: string, agent: SyntheticAgent) {
  await apiFetch(baseUrl, agent, "GET /game-searches/my", "/game-searches/my");
}

async function sendMatchMessage(baseUrl: string, agent: SyntheticAgent, tick: number) {
  const payload = await apiFetch<{ matches?: Array<{ id: string }> }>(baseUrl, agent, "GET /matches", "/matches");
  const match = payload.matches?.[0];

  if (!match) {
    return;
  }

  await apiFetch(baseUrl, agent, "POST /matches/:id/messages", `/matches/${match.id}/messages`, {
    method: "POST",
    body: JSON.stringify({
      text: `Synthetic message from ${agent.name}, tick ${tick}.`
    })
  });
}

async function runAgentTick(baseUrl: string, agent: SyntheticAgent, tick: number) {
  await refreshProfile(baseUrl, agent);
  await discoverAndSwipe(baseUrl, agent, tick);
  await createSearch(baseUrl, agent, tick);
  await respondToSearch(baseUrl, agent);
  await readOwnSearches(baseUrl, agent);
  await sendMatchMessage(baseUrl, agent, tick);
}

function printMetrics() {
  const rows = Array.from(metrics.values()).sort((left, right) => left.name.localeCompare(right.name));
  for (const row of rows) {
    const avgMs = row.count > 0 ? Math.round(row.totalMs / row.count) : 0;
    console.log(`${row.name}: count=${row.count}, failed=${row.failed}, avgMs=${avgMs}`);
  }
}

async function sleep(ms: number) {
  if (ms <= 0) {
    return;
  }
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const options = parseOptions();
  assertSafeTarget(options);

  if (options.reset) {
    await resetSyntheticUsers();
  }

  const agents = await createAgents(options.agents);
  console.log(`Synthetic agents ready: ${agents.length}. Target: ${options.baseUrl}. Ticks: ${options.ticks}.`);

  for (let tick = 1; tick <= options.ticks; tick += 1) {
    const results = await Promise.allSettled(agents.map((agent) => runAgentTick(options.baseUrl, agent, tick)));
    const failed = results.filter((result) => result.status === "rejected");

    for (const failure of failed) {
      console.error(failure.reason);
    }

    console.log(`[tick ${tick}] completed=${results.length - failed.length}, failed=${failed.length}`);
    await sleep(options.intervalMs);
  }

  printMetrics();

  const failedCalls = Array.from(metrics.values()).reduce((sum, metric) => sum + metric.failed, 0);
  if (failedCalls > 0) {
    process.exitCode = 1;
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
