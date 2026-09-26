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

/** +7 999 123-45-67 — для писем, экранов и админки. */
export function formatRussianPhone(phone: string) {
  const match = /^\+7(\d{3})(\d{3})(\d{2})(\d{2})$/.exec(phone);
  return match ? `+7 ${match[1]} ${match[2]}-${match[3]}-${match[4]}` : phone;
}
