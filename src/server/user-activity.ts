import { prisma } from "@/lib/prisma";

export async function touchUserActivity(userId: string) {
  await prisma.user.update({
    where: { id: userId },
    data: {
      lastActiveAt: new Date()
    }
  });
}
