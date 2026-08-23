import { Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";

const DEFAULT_SERIALIZABLE_ATTEMPTS = 3;

export async function withSerializableTransactionRetry<T>(
  operation: (transaction: Prisma.TransactionClient) => Promise<T>,
  maxAttempts = DEFAULT_SERIALIZABLE_ATTEMPTS
): Promise<T> {
  return retryPrismaWriteConflict(
    () =>
      prisma.$transaction(operation, {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable
      }),
    maxAttempts
  );
}

export async function retryPrismaWriteConflict<T>(operation: () => Promise<T>, maxAttempts: number): Promise<T> {
  const attempts = Math.max(1, maxAttempts);

  for (let attempt = 1; ; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      if (attempt >= attempts || !isPrismaWriteConflict(error)) {
        throw error;
      }
    }
  }
}

function isPrismaWriteConflict(error: unknown) {
  return typeof error === "object" && error !== null && "code" in error && error.code === "P2034";
}
