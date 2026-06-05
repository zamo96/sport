import nodemailer from "nodemailer";

type SendOtpEmailInput = {
  to: string;
  code: string;
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

function buildOtpText(code: string) {
  return [
    "Код входа в TennisSearch:",
    "",
    code,
    "",
    "Код действует 10 минут. Если ты не запрашивал вход, просто проигнорируй это письмо."
  ].join("\n");
}

function buildOtpHtml(code: string) {
  return `
    <div style="font-family: Arial, sans-serif; color: #10231b; line-height: 1.5;">
      <p>Код входа в TennisSearch:</p>
      <p style="font-size: 28px; font-weight: 700; letter-spacing: 4px; margin: 16px 0;">${code}</p>
      <p>Код действует 10 минут. Если ты не запрашивал вход, просто проигнорируй это письмо.</p>
    </div>
  `;
}

export async function sendOtpEmail({ to, code }: SendOtpEmailInput) {
  const mode = resolveEmailMode();

  if (mode === "console") {
    console.log(`[auth] OTP for ${to}: ${code}`);
    return;
  }

  if (mode !== "smtp") {
    throw new Error(`Unsupported EMAIL_PROVIDER: ${mode}`);
  }

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST?.trim() || "postbox.cloud.yandex.net",
    port: Number(process.env.SMTP_PORT ?? 587),
    secure: process.env.SMTP_SECURE === "true",
    auth: {
      user: requiredEnv("SMTP_USER"),
      pass: requiredEnv("SMTP_PASSWORD")
    }
  });

  await transporter.sendMail({
    from: requiredEnv("EMAIL_FROM"),
    to,
    subject: "Код входа в TennisSearch",
    text: buildOtpText(code),
    html: buildOtpHtml(code)
  });
}
