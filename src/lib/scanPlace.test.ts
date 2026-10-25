import { describe, expect, it } from 'vitest';
import { scanCountry, scanPlace } from './scanPlace';

describe('scan places', () => {
  it.each([
    ['Basildon, GB', undefined, 'GB', 'Basildon'],
    ['Haiger, DE', 'DE', 'DE', 'Haiger'],
    ['Haiger (DE)', 'DE', 'DE', 'Haiger'],
    ['Paris, FR', 'FR', 'FR', 'Paris'],
    ['Toronto, CA', 'CA', 'CA', 'Toronto'],
    // A state, province or canton keeps its code when the scan was placed elsewhere, or nowhere.
    ['Wilmington, DE', 'US', null, 'Wilmington, DE'],
    ['Austin, TX', 'US', null, 'Austin, TX'],
    ['Los Angeles, CA', 'US', null, 'Los Angeles, CA'],
    ['Fribourg, FR', 'CH', null, 'Fribourg, FR'],
    ['Hannover, DE', undefined, null, 'Hannover, DE'],
  ])('reads %s placed in %s as %s, %s', (location, placed, country, place) => {
    expect(scanPlace(location, placed)).toEqual({ country, place });
  });

  it('counts a final field only, settled by where the scan was placed', () => {
    expect(scanCountry('Zürich, CH')).toBe('CH');
    expect(scanCountry('Haiger, DE', 'DE')).toBe('DE');
    expect(scanCountry('Wilmington, DE', 'US')).toBeNull();
    expect(scanCountry('Austin, TX', 'US')).toBeNull();
    // Never a country guessed from a town, wherever it was placed.
    expect(scanCountry('Basel', 'CH')).toBeNull();
    expect(scanCountry(undefined, 'DE')).toBeNull();
  });
});
