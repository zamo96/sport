import { resolveLocationFromCity, type Coordinates } from "@/lib/geo";
import { validCoordinates } from "@/lib/nearby";
import { prisma } from "@/lib/prisma";

type LocationOwner = { city?: string | null; locationPlaceId?: string | null; homeLat?: number | null; homeLng?: number | null };

/** Resolve an origin without geocoding side effects or changing the saved profile. */
export async function resolveNearbyOrigin(owner: LocationOwner | null, selectedCity?: string, selectedPlaceId?: string) {
  const city = selectedCity?.trim() || owner?.city?.trim();
  const sameCity = !selectedCity || selectedCity.trim().toLowerCase() === owner?.city?.trim().toLowerCase();
  const placeId = selectedPlaceId || (sameCity ? owner?.locationPlaceId : null);
  if (placeId) {
    const place = await prisma.geoPlace.findUnique({ where: { id: placeId } });
    const coordinates = place ? { lat: place.latitude, lng: place.longitude } : null;
    if (validCoordinates(coordinates)) return { city: place!.city, coordinates, locationPlaceId: place!.id };
    // An unresolved canonical identity must not become a different same-named city.
    return null;
  }
  if (!city) return null;
  const preset = await resolveLocationFromCity(city);
  if (validCoordinates(preset)) return { city, coordinates: preset, locationPlaceId: null };
  if (sameCity && owner?.homeLat != null && owner.homeLng != null) {
    const coordinates: Coordinates = { lat: owner.homeLat, lng: owner.homeLng };
    if (validCoordinates(coordinates)) return { city, coordinates, locationPlaceId: null };
  }
  // A name alone is usable only when our canonical catalog has exactly one match.
  const places = await prisma.geoPlace.findMany({ where: { city: { equals: city, mode: "insensitive" } }, take: 2 });
  if (places.length !== 1) return null;
  const coordinates = { lat: places[0].latitude, lng: places[0].longitude };
  return validCoordinates(coordinates) ? { city: places[0].city, coordinates, locationPlaceId: places[0].id } : null;
}
