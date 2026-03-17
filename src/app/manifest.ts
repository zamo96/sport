import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Теннисный партнер",
    short_name: "Теннис",
    description: "Поиск партнера по спорту со свайпами, быстрым мэтчингом и выбором площадки.",
    start_url: "/",
    display: "standalone",
    background_color: "#F4EFE6",
    theme_color: "#126A4A",
    icons: [
      {
        src: "/pwa/icon-192",
        sizes: "192x192",
        type: "image/png"
      },
      {
        src: "/pwa/icon-512",
        sizes: "512x512",
        type: "image/png"
      }
    ]
  };
}
