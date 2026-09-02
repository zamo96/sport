import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { registerPushDeviceSchema } from "@/lib/validators";
import { lockActiveUsersForMutation } from "@/server/account-status";

export async function POST(request: Request) {
  try {
    const user = await requireSessionUser();
    const body = registerPushDeviceSchema.parse(await request.json());

    const device = await prisma.$transaction(async (tx) => {
      const lockedUserIds = await lockActiveUsersForMutation(tx, [user.id]);
      if (!lockedUserIds.has(user.id)) {
        throw new Error("ACCOUNT_DEACTIVATED");
      }

      return tx.pushDevice.upsert({
        where: {
          token: body.token
        },
        update: {
          userId: user.id,
          platform: body.platform,
          environment: body.environment,
          bundleId: body.bundleId,
          deviceName: body.deviceName ?? null,
          locale: body.locale ?? null,
          isActive: true,
          lastRegisteredAt: new Date(),
          lastFailureAt: null,
          lastFailureReason: null
        },
        create: {
          userId: user.id,
          platform: body.platform,
          environment: body.environment,
          token: body.token,
          bundleId: body.bundleId,
          deviceName: body.deviceName ?? null,
          locale: body.locale ?? null,
          isActive: true
        }
      });
    });

    return ok({
      device: {
        id: device.id,
        token: device.token,
        environment: device.environment,
        bundleId: device.bundleId,
        isActive: device.isActive
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "ACCOUNT_DEACTIVATED") {
      return fail("Аккаунт деактивирован", 403);
    }

    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
