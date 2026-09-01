declare module "world-cities-json" {
  export type WorldCitiesJsonRow = {
    city: string;
    city_ascii: string;
    lat: string;
    lng: string;
    country: string;
    iso2: string;
    iso3: string;
    admin_name: string;
    capital: "primary" | "admin" | "minor" | "";
    population: string;
    id: string;
  };

  export const cities: WorldCitiesJsonRow[];
}
