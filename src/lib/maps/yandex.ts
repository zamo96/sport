type YandexMapsApi = {
  ready: Promise<void>;
  YMap: new (container: HTMLElement, props: Record<string, unknown>) => YMapInstance;
  YMapDefaultSchemeLayer: new (props?: Record<string, unknown>) => unknown;
  YMapDefaultFeaturesLayer: new (props?: Record<string, unknown>) => unknown;
  YMapMarker: new (props: Record<string, unknown>, element?: HTMLElement) => unknown;
  YMapFeature?: new (props: Record<string, unknown>) => unknown;
  YMapListener?: new (props: {
    onUpdate?: (event: {
      location?: {
        center?: [number, number];
        zoom?: number;
      };
    }) => void;
  }) => unknown;
};

type YMapInstance = {
  addChild: (child: unknown) => YMapInstance;
  removeChild?: (child: unknown) => YMapInstance;
  destroy: () => void;
};

declare global {
  interface Window {
    ymaps3?: YandexMapsApi;
  }
}

let yandexMapsPromise: Promise<YandexMapsApi> | null = null;

export function loadYandexMaps(apiKey: string, lang = "ru_RU") {
  if (typeof window === "undefined") {
    return Promise.reject(new Error("Yandex Maps can only be loaded in the browser"));
  }

  if (!apiKey) {
    return Promise.reject(new Error("Yandex Maps API key is missing"));
  }

  if (window.ymaps3) {
    return window.ymaps3.ready.then(() => window.ymaps3 as YandexMapsApi);
  }

  if (yandexMapsPromise) {
    return yandexMapsPromise;
  }

  yandexMapsPromise = new Promise<YandexMapsApi>((resolve, reject) => {
    const existingScript = document.querySelector<HTMLScriptElement>('script[data-map-provider="yandex"]');

    if (existingScript) {
      existingScript.addEventListener("load", () => {
        if (!window.ymaps3) {
          reject(new Error("Yandex Maps script loaded, but ymaps3 is unavailable"));
          return;
        }

        window.ymaps3.ready.then(() => resolve(window.ymaps3 as YandexMapsApi)).catch(reject);
      });
      existingScript.addEventListener("error", () => reject(new Error("Failed to load Yandex Maps script")));
      return;
    }

    const script = document.createElement("script");
    script.src = `https://api-maps.yandex.ru/v3/?apikey=${encodeURIComponent(apiKey)}&lang=${encodeURIComponent(lang)}`;
    script.async = true;
    script.dataset.mapProvider = "yandex";
    script.onload = () => {
      if (!window.ymaps3) {
        reject(new Error("Yandex Maps script loaded, but ymaps3 is unavailable"));
        return;
      }

      window.ymaps3.ready.then(() => resolve(window.ymaps3 as YandexMapsApi)).catch(reject);
    };
    script.onerror = () => reject(new Error("Failed to load Yandex Maps script"));
    document.head.appendChild(script);
  });

  return yandexMapsPromise;
}
