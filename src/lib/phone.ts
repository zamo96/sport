/**
 * Российский мобильный номер в виде +79XXXXXXXXX. Вход по SMS принимает только
 * такие номера: закон требует номер российского оператора, а заодно это
 * отсекает накрутку SMS на дорогие международные направления.
 */
export function normalizeRussianMobile(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  let national: string;
  if (digits.length === 11 && (digits.startsWith("7") || digits.startsWith("8"))) {
    national = digits.slice(1);
  } else if (digits.length === 10) {
    national = digits;
  } else {
    return null;
  }
  return /^9\d{9}$/.test(national) ? `+7${national}` : null;
}

/**
 * Цифры номера после +7 — то, что человек вводит в поле телефона. Вставленный
 * номер в любом виде («+7 (999) 123-45-67», «8 999…») сводится к 10 цифрам.
 */
export function russianPhoneDigits(input: string) {
  let digits = input.replace(/\D/g, "");
  if (digits.length === 11 && (digits.startsWith("7") || digits.startsWith("8"))) {
    digits = digits.slice(1);
  }
  return digits.slice(0, 10);
}

/** «999 123-45-67» — как показывать цифры после +7 прямо во время ввода. */
export function formatRussianPhoneDigits(digits: string) {
  const d = digits.slice(0, 10);
  let out = d.slice(0, 3);
  if (d.length > 3) out += ` ${d.slice(3, 6)}`;
  if (d.length > 6) out += `-${d.slice(6, 8)}`;
  if (d.length > 8) out += `-${d.slice(8, 10)}`;
  return out;
}

/** +7 999 123-45-67 — для писем, экранов и админки. */
export function formatRussianPhone(phone: string) {
  const match = /^\+7(\d{3})(\d{3})(\d{2})(\d{2})$/.exec(phone);
  return match ? `+7 ${match[1]} ${match[2]}-${match[3]}-${match[4]}` : phone;
}
