declare module "tz-lookup" {
  /** Возвращает имя IANA-зоны для координат; бросает исключение на некорректных значениях. */
  export default function tzLookup(latitude: number, longitude: number): string;
}
