import { describe, expect, it } from "vitest";

import {
  extractBookingUrls,
  extractClubWebsiteSnapshot,
  extractBookingUrlEvidence,
  extractClosureSignals,
  extractPhoneEvidence,
  extractPhones,
  normalizeWebsiteText
} from "@/lib/club-website";

describe("club website extraction", () => {
  const html = `
    <!doctype html>
    <html>
      <head>
        <title>Теннисный клуб Север</title>
        <meta name="description" content="Крытые корты, тренировки и аренда в Санкт-Петербурге">
        <script>window.dynamic = "ignore me";</script>
      </head>
      <body>
        <h1>Теннисный клуб Север</h1>
        <p>Телефон: +7 (812) 123-45-67</p>
        <a href="/booking">Забронировать корт</a>
        <a href="https://example.com/news">Новости</a>
      </body>
    </html>
  `;

  it("normalizes visible website text without scripts", () => {
    const text = normalizeWebsiteText(html);

    expect(text).toContain("Теннисный клуб Север");
    expect(text).toContain("+7 (812) 123-45-67");
    expect(text).not.toContain("ignore me");
  });

  it("extracts stable website snapshot fields", () => {
    const snapshot = extractClubWebsiteSnapshot(html, "https://club.example.com");

    expect(snapshot.title).toBe("Теннисный клуб Север");
    expect(snapshot.description).toContain("Крытые корты");
    expect(snapshot.detectedPhones).toEqual(["78121234567"]);
    expect(snapshot.detectedBookingUrls).toEqual(["https://club.example.com/booking"]);
    expect(snapshot.phoneEvidence[0]).toMatchObject({
      value: "78121234567",
      source: "visible_text"
    });
    expect(snapshot.bookingUrlEvidence[0]).toMatchObject({
      value: "https://club.example.com/booking",
      source: "booking_link",
      sameHost: true
    });
    expect(snapshot.contentHash).toMatch(/^[a-f0-9]{64}$/);
  });

  it("extracts booking links from href and label hints", () => {
    expect(extractBookingUrls(html, "https://club.example.com")).toEqual(["https://club.example.com/booking"]);
  });

  it("prefers tel links as phone evidence", () => {
    const evidence = extractPhoneEvidence('<a href="tel:+78121234567">+7 (812) 123-45-67</a>', "+7 (812) 123-45-67");

    expect(evidence[0]).toMatchObject({
      value: "78121234567",
      source: "tel_link",
      confidence: 0.96
    });
  });

  it("ignores social links as booking evidence", () => {
    const evidence = extractBookingUrlEvidence(
      '<a href="https://facebook.com/freshitnessspb/">Записаться</a><a href="/raspisanie">Расписание</a>',
      "https://fresh-tennis.ru"
    );

    expect(evidence.map((item) => item.value)).toEqual(["https://fresh-tennis.ru/raspisanie"]);
  });

  it("extracts closure and relocation signals", () => {
    expect(extractClosureSignals("Клуб временно закрыт, временно не работает, переезд на новый адрес")).toEqual([
      "временно закрыт",
      "клуб закрыт",
      "временно не работает",
      "переезд",
      "новый адрес"
    ]);
  });

  it("does not treat covered courts text as a closure signal", () => {
    expect(extractClosureSignals("Занятия проходят на закрытых и крытых кортах весь сезон")).toEqual([]);
  });

  it("deduplicates normalized phones", () => {
    expect(extractPhones("+7 (812) 123-45-67, 8 812 123 45 67")).toEqual(["78121234567"]);
  });

  it("ignores phone placeholders from embedded forms", () => {
    expect(extractPhones("Маска поля телефона +7 (999) 999-99-99, контакты +7 (812) 123-45-67")).toEqual([
      "78121234567"
    ]);
  });
});
