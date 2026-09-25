import type { Metadata, Viewport } from "next";
import { Manrope, Space_Grotesk } from "next/font/google";

import { WebActivityTracker } from "@/components/analytics/web-activity-tracker";
import { ConsentReviewGate } from "@/components/consents/consent-review-gate";
import { BottomNav } from "@/components/layout/bottom-nav";
import { SWRegister } from "@/components/layout/sw-register";
import { LocaleProvider } from "@/components/i18n/locale-provider";
import { getWebRequestLocale } from "@/lib/i18n/web/request-locale";

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
  title: "SportSearch",
  description: "Find sports partners, choose a court, and arrange a game.",
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
  const initialLocale = getWebRequestLocale();

  return (
    <html lang={initialLocale}>
      <body className={`${bodyFont.variable} ${headingFont.variable} font-sans`}>
        <LocaleProvider initialLocale={initialLocale}>
          <SWRegister />
          <WebActivityTracker />
          {children}
          <BottomNav />
          <ConsentReviewGate />
        </LocaleProvider>
      </body>
    </html>
  );
}
