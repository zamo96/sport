import { getEffectiveClientLocale } from "@/lib/client-locale";

export async function apiFetch<T>(input: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers);
  headers.set("Content-Type", "application/json");
  headers.set("Accept-Language", getEffectiveClientLocale());

  const response = await fetch(input, {
    ...init,
    headers
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(data.error ?? (getEffectiveClientLocale() === "ru" ? "Запрос завершился ошибкой" : "Request failed"));
  }

  return data as T;
}
