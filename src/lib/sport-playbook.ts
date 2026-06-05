import { PlayFormat, Sport } from "@prisma/client";

export type SportPlaybookEntry = {
  sport: Sport;
  allowedFormats: PlayFormat[];
  defaultFormat: PlayFormat;
  defaultDurationMinutes: number;
  defaultPlayersNeededByFormat: Record<PlayFormat, number>;
  maxPlayersNeeded: number;
};

const PLAYBOOK: Record<Sport, SportPlaybookEntry> = {
  tennis: {
    sport: "tennis",
    allowedFormats: [PlayFormat.singles, PlayFormat.doubles, PlayFormat.both],
    defaultFormat: PlayFormat.singles,
    defaultDurationMinutes: 90,
    defaultPlayersNeededByFormat: {
      singles: 1,
      doubles: 3,
      both: 1
    },
    maxPlayersNeeded: 8
  },
  padel: {
    sport: "padel",
    allowedFormats: [PlayFormat.doubles],
    defaultFormat: PlayFormat.doubles,
    defaultDurationMinutes: 90,
    defaultPlayersNeededByFormat: {
      singles: 3,
      doubles: 3,
      both: 3
    },
    maxPlayersNeeded: 8
  },
  badminton: {
    sport: "badminton",
    allowedFormats: [PlayFormat.singles, PlayFormat.doubles, PlayFormat.both],
    defaultFormat: PlayFormat.both,
    defaultDurationMinutes: 60,
    defaultPlayersNeededByFormat: {
      singles: 1,
      doubles: 3,
      both: 1
    },
    maxPlayersNeeded: 8
  },
  table_tennis: {
    sport: "table_tennis",
    allowedFormats: [PlayFormat.singles],
    defaultFormat: PlayFormat.singles,
    defaultDurationMinutes: 60,
    defaultPlayersNeededByFormat: {
      singles: 1,
      doubles: 1,
      both: 1
    },
    maxPlayersNeeded: 8
  },
  squash: {
    sport: "squash",
    allowedFormats: [PlayFormat.singles],
    defaultFormat: PlayFormat.singles,
    defaultDurationMinutes: 60,
    defaultPlayersNeededByFormat: {
      singles: 1,
      doubles: 1,
      both: 1
    },
    maxPlayersNeeded: 8
  },
  football: {
    sport: "football",
    allowedFormats: [PlayFormat.doubles],
    defaultFormat: PlayFormat.doubles,
    defaultDurationMinutes: 90,
    defaultPlayersNeededByFormat: {
      singles: 9,
      doubles: 9,
      both: 9
    },
    maxPlayersNeeded: 12
  },
  volleyball: {
    sport: "volleyball",
    allowedFormats: [PlayFormat.doubles],
    defaultFormat: PlayFormat.doubles,
    defaultDurationMinutes: 90,
    defaultPlayersNeededByFormat: {
      singles: 5,
      doubles: 5,
      both: 5
    },
    maxPlayersNeeded: 12
  },
  fitness: {
    sport: "fitness",
    allowedFormats: [PlayFormat.singles, PlayFormat.both],
    defaultFormat: PlayFormat.singles,
    defaultDurationMinutes: 60,
    defaultPlayersNeededByFormat: {
      singles: 1,
      doubles: 1,
      both: 1
    },
    maxPlayersNeeded: 8
  },
  boxing: {
    sport: "boxing",
    allowedFormats: [PlayFormat.singles, PlayFormat.both],
    defaultFormat: PlayFormat.singles,
    defaultDurationMinutes: 60,
    defaultPlayersNeededByFormat: {
      singles: 1,
      doubles: 1,
      both: 1
    },
    maxPlayersNeeded: 8
  },
  yoga: {
    sport: "yoga",
    allowedFormats: [PlayFormat.singles, PlayFormat.both],
    defaultFormat: PlayFormat.singles,
    defaultDurationMinutes: 60,
    defaultPlayersNeededByFormat: {
      singles: 1,
      doubles: 1,
      both: 1
    },
    maxPlayersNeeded: 8
  }
};

export function getSportPlaybook(sport: Sport): SportPlaybookEntry {
  return PLAYBOOK[sport] ?? PLAYBOOK.tennis;
}

export function resolveFormatForSport(sport: Sport, requested: PlayFormat) {
  const playbook = getSportPlaybook(sport);
  return playbook.allowedFormats.includes(requested) ? requested : playbook.defaultFormat;
}

export function isFormatAllowedForSport(sport: Sport, format: PlayFormat) {
  return getSportPlaybook(sport).allowedFormats.includes(format);
}

export function getSportFormatOptions(sport: Sport) {
  return getSportPlaybook(sport).allowedFormats;
}

export function getDefaultSportFormat(sport: Sport) {
  return getSportPlaybook(sport).defaultFormat;
}

export function getDefaultDurationMinutes(sport: Sport) {
  return getSportPlaybook(sport).defaultDurationMinutes;
}

export function getDefaultPlayersNeeded(sport: Sport, format: PlayFormat) {
  const playbook = getSportPlaybook(sport);
  const resolvedFormat = resolveFormatForSport(sport, format);
  return playbook.defaultPlayersNeededByFormat[resolvedFormat] ?? 1;
}

export function getMaxPlayersNeeded(sport: Sport) {
  return getSportPlaybook(sport).maxPlayersNeeded;
}
