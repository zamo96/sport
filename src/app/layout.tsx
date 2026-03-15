import type { Metadata, Viewport } from "next";
import { Manrope, Space_Grotesk } from "next/font/google";

import { BottomNav } from "@/components/layout/bottom-nav";
import { SWRegister } from "@/components/layout/sw-register";

import "./globals.css";

const bodyFont = Manrope({
  subsets: ["latin", "cyrillic"],
  variable: "--font-body"
});

const headingFont = Space_Grotesk({
  subsets: ["latin"],
  variable: "--font-heading"
});

export const metadata: Metadata = {
  title: "Поиск партнера для игры",
  description: "Быстрый поиск партнера по ракетным видам спорта, мэтчинг, выбор корта и договоренность об игре.",
  manifest: "/manifest.webmanifest"
};

export const viewport: Viewport = {
  themeColor: "#126A4A",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ru">
      <body className={`${bodyFont.variable} ${headingFont.variable} font-sans`}>
        <SWRegister />
        {children}
        <BottomNav />
      </body>
    </html>
  );
}
