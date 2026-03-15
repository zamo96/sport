export async function apiFetch<T>(input: string, init?: RequestInit): Promise<T> {
  const response = await fetch(input, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {})
    }
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(data.error ?? "Запрос завершился ошибкой");
  }

  return data as T;
}
