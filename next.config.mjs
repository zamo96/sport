/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    typedRoutes: false
  },
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "storage.yandexcloud.net"
      },
      {
        protocol: "https",
        hostname: "*.storage.yandexcloud.net"
      }
    ]
  }
};

export default nextConfig;
