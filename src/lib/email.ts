import nodemailer from "nodemailer";

import { getConfiguredAdminEmails } from "@/lib/admin";
import { translateServer } from "@/lib/i18n/server";
import type { SupportedLocale } from "@/lib/locales";

type SendOtpEmailInput = {
  to: string;
  code: string;
  locale: SupportedLocale;
};

function requiredEnv(name: string) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required env: ${name}`);
  }
  return value;
}

function resolveEmailMode() {
  return process.env.EMAIL_PROVIDER?.trim() || (process.env.NODE_ENV === "production" ? "smtp" : "console");
}

function smtpTransporter() {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST?.trim() || "postbox.cloud.yandex.net",
    port: Number(process.env.SMTP_PORT ?? 587),
    secure: process.env.SMTP_SECURE === "true",
    auth: {
      user: requiredEnv("SMTP_USER"),
      pass: requiredEnv("SMTP_PASSWORD")
    }
  });
}

export function buildOtpEmail(code: string, locale: SupportedLocale) {
  const heading = translateServer(locale, "auth.email.heading");
  const expiry = translateServer(locale, "auth.email.expiry");
  const text = [
    heading,
    "",
    code,
    "",
    expiry
  ].join("\n");
  const html = `
    <div style="font-family: Arial, sans-serif; color: #10231b; line-height: 1.5;">
      <p>${heading}</p>
      <p style="font-size: 28px; font-weight: 700; letter-spacing: 4px; margin: 16px 0;">${code}</p>
      <p>${expiry}</p>
    </div>
  `;

  return {
    subject: translateServer(locale, "auth.email.subject"),
    text,
    html
  };
}

export async function sendOtpEmail({ to, code, locale }: SendOtpEmailInput) {
  const mode = resolveEmailMode();

  if (mode === "console") {
    console.log(`[auth] OTP for ${to}: ${code}`);
    return;
  }

  if (mode !== "smtp") {
    throw new Error(`Unsupported EMAIL_PROVIDER: ${mode}`);
  }

  const transporter = smtpTransporter();
  const message = buildOtpEmail(code, locale);

  await transporter.sendMail({
    from: requiredEnv("EMAIL_FROM"),
    to,
    ...message
  });
}

export async function sendContentReportAlert({
  reportId,
  dueAt,
  origin
}: {
  reportId: string;
  dueAt: Date;
  origin: "report" | "block";
}) {
  const recipients = getConfiguredAdminEmails();
  if (recipients.length === 0) return;

  const mode = resolveEmailMode();
  if (mode === "console") {
    console.info(`[moderation] New ${origin} report ${reportId}; due ${dueAt.toISOString()}`);
    return;
  }
  if (mode !== "smtp") throw new Error(`Unsupported EMAIL_PROVIDER: ${mode}`);

  const adminUrl = `${process.env.NEXT_PUBLIC_APP_URL?.replace(/\/$/, "") || "https://sportsearch.shop"}/admin/reports/${reportId}`;
  const text = [
    "Получена новая жалоба на пользовательский контент.",
    `ID: ${reportId}`,
    `Источник: ${origin}`,
    `Проверить до: ${dueAt.toISOString()}`,
    `Открыть: ${adminUrl}`
  ].join("\n");

  await smtpTransporter().sendMail({
    from: requiredEnv("EMAIL_FROM"),
    to: recipients,
    subject: `SportSearch: новая жалоба ${reportId}`,
    text
  });
}
