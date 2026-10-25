import { trackingLocationCountry, trackingPlace, type TrackingPlace } from 'universal-parcel-scraper/app';

/** A final two-letter field, as in "Haiger, DE" or "Haiger (DE)". */
const FINAL_CODE = /^(.*\S)\s*[,;|(]\s*([A-Z]{2})\)?$/;

/**
 * The final code of a location, with what comes before it, when it is the country the server placed the scan in. A
 * code that is also a state, province or canton ("Haiger, DE", "Wilmington, DE", "Toronto, CA", "Los Angeles, CA")
 * is not read as a country on its own; where the scan was placed settles it.
 */
function placedCode(location: string, placed: string | null | undefined): { country: string; place: string } | null {
  const code = placed ? FINAL_CODE.exec(location.trim()) : null;
  return code && code[2] === placed ? { country: placed, place: code[1] } : null;
}

/** A scan's location for display: the country it names, and the rest of it. */
export function scanPlace(location: string, placed?: string | null): TrackingPlace {
  const written = trackingPlace(location);
  return written.country ? written : placedCode(location, placed) ?? written;
}

/** The country a scan's location names in its final field, as the passport counts it: never one guessed from a town. */
export function scanCountry(location: string | undefined, placed?: string | null): string | null {
  return trackingLocationCountry(location) ?? (location ? placedCode(location, placed)?.country ?? null : null);
}
