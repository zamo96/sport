import { ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET() {
  const [registeredPlayersCount, seekingPlayersCount] = await Promise.all([
    prisma.user.count({
      where: {
        isVerified: true,
        onboardingCompleted: true
      }
    }),
    prisma.user.count({
      where: {
        isVerified: true,
        onboardingCompleted: true,
        OR: [
          {
            isLookingForGame: true
          },
          {
            gameSearches: {
              some: {
                isActive: true
              }
            }
          }
        ]
      }
    })
  ]);

  return ok({
    registeredPlayersCount,
    seekingPlayersCount
  });
}
