import type { Sport } from "@prisma/client";

import type { SupportedLocale } from "@/lib/locales";
import {
  SPORT_LEVEL_GUIDES,
  type SportLevelGuideEntry
} from "@/lib/sport-level-guides";

type TenLevelGuide = readonly [
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry,
  SportLevelGuideEntry
];

export const ENGLISH_SPORT_LEVEL_GUIDES = {
  table_tennis: [
    { level: 1, title: "First contact", description: "You rarely connect with the ball and are just getting used to your stance, grip, and the bounce." },
    { level: 2, title: "Basic strokes", description: "You can start a rally from close range and return the ball to the table several times." },
    { level: 3, title: "Recreational start", description: "You understand the service rules and can return simple balls without heavy spin." },
    { level: 4, title: "Finding the rhythm", description: "You can sustain a short rally, change direction, and miss the table less often." },
    { level: 5, title: "Confident recreational player", description: "You can reliably play a game with recreational players, and your serve and return no longer break down the rally." },
    { level: 6, title: "Control and speed", description: "You can play at pace and control flat shots and balls with moderate spin." },
    { level: 7, title: "Strong player", description: "You use spin deliberately, construct points, and read your opponent's serve." },
    { level: 8, title: "Advanced recreational player", description: "You rarely give away easy balls, can apply pressure early, and sustain a high tempo." },
    { level: 9, title: "Tournament level", description: "You compete confidently in local tournaments and vary your serve, spin, and pace." },
    { level: 10, title: "Very high level", description: "Your technique and pace remain consistently strong even against skilled opponents." }
  ],
  tennis: [
    { level: 1, title: "First strokes", description: "You are just getting familiar with the racket and scoring and are learning to hit the ball over the net." },
    { level: 2, title: "Beginner", description: "You can make individual forehand and backhand shots, but long rallies are still rare." },
    { level: 3, title: "Basic foundation", description: "You can sustain a short rally from a slow ball and know how to keep score in games." },
    { level: 4, title: "Recreational rhythm", description: "You can put your serve in play, move around the court, and play practice sets." },
    { level: 5, title: "Confident recreational player", description: "You keep the ball in the court consistently, play matches with recreational players, and understand basic tactics." },
    { level: 6, title: "Composed player", description: "You control depth, attack comfortable balls, and keep your serve reliable under pressure." },
    { level: 7, title: "Strong sparring level", description: "You can handle an intense pace, defend effectively, and finish attacks within one or two shots." },
    { level: 8, title: "Advanced", description: "You stay consistent under pressure, serve well, and play confidently across the whole court." },
    { level: 9, title: "Recreational tournament player", description: "You are comfortable in recreational tournaments and rarely give away easy points." },
    { level: 10, title: "Very high level", description: "Your technique, fitness, and match pace are close to a semi-professional level." }
  ],
  padel: [
    { level: 1, title: "First walls", description: "You are getting used to the padel format, rebounds off the glass, and court positioning." },
    { level: 2, title: "Starting rhythm", description: "You can return a simple ball and are beginning to understand how to play off the wall." },
    { level: 3, title: "Getting comfortable", description: "You can sustain short rallies and know where to position yourself with a partner." },
    { level: 4, title: "Recreational pace", description: "You can play a set without chaos and understand the basic transition from defense to attack." },
    { level: 5, title: "Confident recreational player", description: "You use the walls intentionally, hold your position, and support your partner." },
    { level: 6, title: "Good control", description: "You are confident at the net and in defense and give away fewer easy balls." },
    { level: 7, title: "Strong pair player", description: "You read the game, vary the pace, and build rallies toward a favorable attack." },
    { level: 8, title: "Advanced padel", description: "You play consistently off the walls, sustain pressure, and understand court geometry as a team." },
    { level: 9, title: "Tournament pace", description: "You are comfortable in amateur tournaments and know how to punish a weak ball." },
    { level: 10, title: "Very high level", description: "You read space quickly, make few mistakes, and maintain a high tempo through most of the match." }
  ],
  squash: [
    { level: 1, title: "Getting to know the court", description: "You are getting used to the walls, the bounce, and positioning around the T." },
    { level: 2, title: "First rallies", description: "You can return a simple ball several times, although the pace is still low." },
    { level: 3, title: "Basic control", description: "You understand the rules, keep the ball in play, and are starting to move around the court deliberately." },
    { level: 4, title: "Recreational level", description: "You can sustain a rally, position yourself more effectively, and reach most balls." },
    { level: 5, title: "Confident recreational player", description: "You control length and can shape a rally into a pattern that suits you." },
    { level: 6, title: "Speed and accuracy", description: "You sustain a high pace, move efficiently, and construct rallies." },
    { level: 7, title: "Strong match level", description: "You make few easy errors, recover well to the T, and understand how to pressure an opponent." },
    { level: 8, title: "Advanced player", description: "You vary length and height and play aggressively while remaining in control." },
    { level: 9, title: "Recreational tournament player", description: "You play competitive matches confidently and can withstand long, intense rallies." },
    { level: 10, title: "Very high level", description: "You combine a high pace, strong endurance, and accurate shots even under heavy pressure." }
  ],
  badminton: [
    { level: 1, title: "First contact", description: "You are getting familiar with the racket, the serve, and the flight of the shuttlecock." },
    { level: 2, title: "Starting to connect", description: "You can send the shuttlecock over the net and sustain a short rally." },
    { level: 3, title: "Getting comfortable", description: "You understand the basic rules and can play confidently at a slow pace." },
    { level: 4, title: "Recreational foundation", description: "You move better around the court, can serve, and stay composed in simple rallies." },
    { level: 5, title: "Confident recreational player", description: "You can direct some of your shots and sustain the pace of a match." },
    { level: 6, title: "Good control", description: "You read the game, place the shuttlecock into open space, and move without rushing." },
    { level: 7, title: "Strong player", description: "You have speed, consistency, and a sense of when to attack or extend the rally." },
    { level: 8, title: "Advanced recreational player", description: "You play confidently in singles and doubles and rarely give away easy points." },
    { level: 9, title: "Tournament pace", description: "You can compete with good pace, a reliable serve, and sound decision-making." },
    { level: 10, title: "Very high level", description: "You combine very fast footwork, shuttle control, and strong technique under serious physical load." }
  ],
  volleyball: [
    { level: 1, title: "First touches", description: "You are learning forearm and overhead passing, the rules, and court positions." },
    { level: 2, title: "Beginner player", description: "You can receive an easy ball and understand how players rotate through positions." },
    { level: 3, title: "Basic team play", description: "You take part in rallies, move within the formation, and are starting to feel the timing." },
    { level: 4, title: "Recreational level", description: "You receive simple balls confidently, support team rallies, and stay composed during play." },
    { level: 5, title: "Confident recreational player", description: "You have a reliable pass, set, or attack at a recreational level and understand your role." },
    { level: 6, title: "Composed player", description: "You stay involved in team play, read the serve, and coordinate better with teammates." },
    { level: 7, title: "Strong match level", description: "You handle a good pace and can make a difference in attack or defense." },
    { level: 8, title: "Advanced", description: "You have consistent technique, good positioning, and a strong understanding of team patterns." },
    { level: 9, title: "Recreational tournament player", description: "You are comfortable in amateur tournaments, read opponents, and rarely lose composure under pressure." },
    { level: 10, title: "Very high level", description: "Your technique and fitness are excellent, and you sustain your level with very few simple lapses." }
  ],
  fitness: [
    { level: 1, title: "Getting started", description: "You are beginning to train regularly and learning basic movements with a coach or a program." },
    { level: 2, title: "Building a routine", description: "You understand the main exercises but are still finding the right technique and working weights." },
    { level: 3, title: "Basic recreational level", description: "You can complete a simple workout confidently and follow a basic plan." },
    { level: 4, title: "Consistent beginner", description: "You train regularly and control your technique in most foundational exercises." },
    { level: 5, title: "Confident level", description: "You have a clear program, consistent discipline, and a good sense of your working loads." },
    { level: 6, title: "Good foundation", description: "You understand volume and recovery and train toward a goal instead of guessing." },
    { level: 7, title: "Advanced recreational athlete", description: "You can adjust training load, technique, and exercises to suit your goals." },
    { level: 8, title: "Strong level", description: "You have trained consistently for a long time and handle significant loads with sound technique." },
    { level: 9, title: "Very experienced", description: "You have practical knowledge of programming training load, nutrition, and recovery." },
    { level: 10, title: "Expert recreational athlete", description: "You have a very high recreational level built on strong technique, consistency, and extensive training experience." }
  ],
  boxing: [
    { level: 1, title: "First session", description: "You are getting familiar with stance, movement, and basic punches." },
    { level: 2, title: "Beginner", description: "You understand the jab and rear straight, but distance and rhythm are still difficult to maintain." },
    { level: 3, title: "Basic foundation", description: "You can put together simple combinations, work on pads, and know the fundamentals of defense." },
    { level: 4, title: "Recreational level", description: "You can sustain a round, move with more purpose, and punch with growing confidence." },
    { level: 5, title: "Confident boxer", description: "You have rhythm, distance control, basic defense, and an understanding of partner work." },
    { level: 6, title: "Good technique", description: "Your combinations, movement, and defense work together, and you are less likely to lose composure in sparring." },
    { level: 7, title: "Strong recreational boxer", description: "You work confidently to a plan, see attacking opportunities, and control the pace." },
    { level: 8, title: "Advanced", description: "You have solid fundamentals, consistent sparring, composed movement, and clear physical readiness." },
    { level: 9, title: "Recreational tournament boxer", description: "You are ready for amateur bouts or already have competitive experience." },
    { level: 10, title: "Very high level", description: "You combine strong technical and physical ability, a high pace, and mature reading of your opponent." }
  ],
  yoga: [
    { level: 1, title: "First class", description: "You are getting familiar with breathing, basic asanas, and body awareness in practice." },
    { level: 2, title: "Beginner", description: "You understand simple sequences, but balance, flexibility, and breathing are still inconsistent." },
    { level: 3, title: "Basic practice", description: "You can complete a calm class and hold foundational poses without rushing." },
    { level: 4, title: "Confident start", description: "You practice regularly, feel your body better, and understand the main transitions." },
    { level: 5, title: "Confident practice", description: "You are comfortable in an intermediate class, breathe more evenly, and work with your body consciously." },
    { level: 6, title: "Good level", description: "You have consistent balance, strength, and mobility and understand pose technique more deeply." },
    { level: 7, title: "Advanced recreational practitioner", description: "You can maintain more complex sequences, distribute effort well, and preserve the quality of your practice." },
    { level: 8, title: "Strong practice", description: "You have strong awareness, flexibility, and control and are comfortable in advanced classes." },
    { level: 9, title: "Very experienced", description: "You have extensive experience and a deep understanding of the body, breath, and asana variations." },
    { level: 10, title: "Expert level", description: "Your practice is highly mature, with strong body control, breath control, and long-term consistency." }
  ],
  football: [
    { level: 1, title: "First games", description: "You are just starting to play and getting used to the ball, your position, and the pace of the pitch." },
    { level: 2, title: "Beginner player", description: "You understand the basic rules and can take part at a simple pace." },
    { level: 3, title: "Basic foundation", description: "You can pass, receive, and move off the ball and already feel comfortable in a recreational game." },
    { level: 4, title: "Recreational level", description: "You understand your role, lose the ball less often, and read situations more effectively." },
    { level: 5, title: "Confident recreational player", description: "You can play a full match, move with purpose, and contribute to combinations." },
    { level: 6, title: "Strong recreational player", description: "You pass well, choose good positions, and know when to speed up or slow down play." },
    { level: 7, title: "Match pace", description: "You play confidently in intense recreational matches and stay involved throughout." },
    { level: 8, title: "Advanced level", description: "You read the game well, maintain a high work rate, and contribute to the team for the whole match." },
    { level: 9, title: "Recreational tournament player", description: "You play consistently in strong recreational teams and sustain a competitive pace." },
    { level: 10, title: "Very high level", description: "Your recreational level is exceptionally strong in technique, positioning, and fitness." }
  ],
  running: [
    { level: 1, title: "Starting to run", description: "You alternate running and walking while getting used to regular sessions and an easy pace." },
    { level: 2, title: "Easy runs", description: "You can run for 15–20 minutes without rushing and are gradually increasing the distance." },
    { level: 3, title: "Consistent start", description: "You run short distances regularly and maintain an even conversational pace." },
    { level: 4, title: "Recreational pace", description: "You can comfortably run 5 km and understand which pace suits you." },
    { level: 5, title: "Confident runner", description: "You run several times a week and can accompany a partner for 5–8 km." },
    { level: 6, title: "Good foundation", description: "You maintain a steady pace, control your breathing, and recover well after runs." },
    { level: 7, title: "Strong recreational runner", description: "You can comfortably run 10 km and adjust your pace to the workout." },
    { level: 8, title: "Advanced", description: "Your training includes intervals and long runs, and you understand how to follow a plan." },
    { level: 9, title: "Competitive pace", description: "You take part in races, hold a target pace, and perform confidently over the distance." },
    { level: 10, title: "Very high level", description: "You have strong endurance, high training volume, and a consistent pace over long distances." }
  ],
  supboard: [
    { level: 1, title: "First experience", description: "You are learning to stand on the board, balance on calm water, and move close to shore." },
    { level: 2, title: "Calm outing", description: "You paddle confidently on short windless routes and can turn without difficulty." },
    { level: 3, title: "Basic technique", description: "You maintain a steady pace and can start, stop, and navigate simple sections of a route." },
    { level: 4, title: "Recreational level", description: "You are comfortable on leisure routes and can handle light waves." },
    { level: 5, title: "Confident paddler", description: "You go out regularly, keep pace with a group, and can paddle for 60 minutes." },
    { level: 6, title: "Good foundation", description: "You control the board in wind, conserve energy, and choose a safe line." },
    { level: 7, title: "Strong recreational paddler", description: "You are comfortable on long routes and maintain a consistent speed." },
    { level: 8, title: "Advanced", description: "You paddle with sound technique, read the water, and can lead a group along a route." },
    { level: 9, title: "Sport pace", description: "You can maintain a high pace, handle difficult sections, and take part in amateur events." },
    { level: 10, title: "Very high level", description: "You have strong technique, endurance, and confidence on long routes and changing water." }
  ]
} as const satisfies Record<Sport, TenLevelGuide>;

export function getLocalizedSportLevelGuide(locale: SupportedLocale, sport: Sport): readonly SportLevelGuideEntry[] {
  return locale === "ru" ? SPORT_LEVEL_GUIDES[sport] : ENGLISH_SPORT_LEVEL_GUIDES[sport];
}
