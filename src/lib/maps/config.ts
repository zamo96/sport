export type MapProvider = "yandex" | "none";

export function getMapProvider(): MapProvider {
  return process.env.NEXT_PUBLIC_MAP_PROVIDER === "yandex" ? "yandex" : "none";
}

export function getYandexMapsApiKey() {
  return process.env.NEXT_PUBLIC_YANDEX_MAPS_API_KEY?.trim() || "";
}
