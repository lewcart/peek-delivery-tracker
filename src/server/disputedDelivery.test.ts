import { describe, expect, it } from 'vitest';
import { DateTime } from 'luxon';
import { carrierTimezone, type CarrierResult } from 'universal-parcel-scraper';
import { carrierMovedAt, showsDelivery, withoutDisputedDelivery } from './disputedDelivery';

// Wording and clocks are invented. Both carriers read local clocks in their catalog zones: SEUR's is Europe/Madrid.
const provider = (delivered: string): CarrierResult => ({ status: 'delivered', current_stage: 'delivered', last_status_text: 'Delivered',
  delivered_at: delivered, last_update: delivered, events: [
    { time: delivered, description: 'Delivered', stage: 'delivered' },
    { time: '2026-10-15T17:13:00Z', description: 'Processed', stage: 'in_transit' },
  ] });
/** The instant BRT's wall clock shows in its catalog zone. */
const onBrtClock = (local: string) => DateTime.fromISO(local, { zone: carrierTimezone('brt') }).toUTC().toISO({ suppressMilliseconds: true })!;
const own = (...events: CarrierResult['events'] & object): CarrierResult => ({ status: 'in_transit', current_stage: 'in_transit',
  last_status_text: 'Delivered by airline', events });

describe('a delivery the parcel\'s own carrier disputes', () => {
  it('goes when the carrier read the same scan as another stage', () => {
    const answer = own({ local_time: '2026-10-15T20:00:00', description: 'Delivered by airline', stage: 'in_transit' });
    const scanned = onBrtClock('2026-10-15T20:00:00');
    expect(withoutDisputedDelivery(provider(scanned), 'unknown', 'brt', answer)).toEqual({
      status: 'in_transit', current_stage: 'in_transit', current_stage_source: undefined, last_status_text: 'Delivered by airline',
      last_update: scanned, events: [{ time: '2026-10-15T17:13:00Z', description: 'Processed', stage: 'in_transit' }],
    });
  });

  it('stands when the carrier last moved the parcel before it, in the carrier\'s zone', () => {
    // 09:53 in Madrid is 07:53 UTC, before the delivery at 08:30 UTC.
    const answer = own({ local_time: '2026-10-20T09:53:00', description: 'En reparto', stage: 'out_for_delivery' });
    expect(withoutDisputedDelivery(provider('2026-10-20T08:30:00Z'), 'unknown', 'seur', answer)).toBeNull();
    expect(withoutDisputedDelivery(provider('2026-10-20T07:30:00Z'), 'unknown', 'seur', answer)).not.toBeNull();
  });

  it('stands when the carrier\'s newer scan has no stage, or the carrier shows a delivery', () => {
    const unread = own({ local_time: '2026-10-20T20:00:00', description: 'Entregado', stage: 'pending' },
      { local_time: '2026-10-20T07:00:00', description: 'En reparto', stage: 'out_for_delivery' });
    expect(carrierMovedAt('seur', unread)).toBe(Date.parse('2026-10-20T05:00:00Z'));
    expect(withoutDisputedDelivery(provider('2026-10-20T18:00:00Z'), 'unknown', 'seur', unread)).toBeNull();
    const delivered = own({ local_time: '2026-10-21T10:00:00', description: 'Consegnata', stage: 'delivered' });
    expect(showsDelivery(delivered)).toBe(true);
    expect(withoutDisputedDelivery(provider('2026-10-20T18:00:00Z'), 'unknown', 'brt', delivered)).toBeNull();
  });

  it('stands when the carrier\'s newer scans are in no stage of their own', () => {
    // Synthetic notices dated after the delivery at 18:00 UTC: one no rule reads, one the carrier says keeps the
    // stage of the scan before it. Neither moved the parcel.
    const delivering = { local_time: '2026-10-20T07:00:00', description: 'En reparto', stage: 'out_for_delivery' };
    for (const notice of [{ local_time: '2026-10-20T21:00:00', description: 'Fixture notice 7' },
      { local_time: '2026-10-20T21:00:00', description: 'Fixture notice 8', stage: 'out_for_delivery', stage_source: 'none' }]) {
      const answer = own(notice, delivering);
      expect(carrierMovedAt('seur', answer)).toBe(Date.parse('2026-10-20T05:00:00Z'));
      expect(withoutDisputedDelivery(provider('2026-10-20T18:00:00Z'), 'unknown', 'seur', answer)).toBeNull();
    }
    // A scan in a stage the carrier gives it, or one its wording reads as, did.
    for (const moved of [{ local_time: '2026-10-20T21:00:00', description: 'Fixture scan 9', stage: 'in_transit', stage_source: 'carrier_map' },
      { local_time: '2026-10-20T21:00:00', description: 'Your parcel is on its way' }]) {
      expect(withoutDisputedDelivery(provider('2026-10-20T18:00:00Z'), 'unknown', 'seur', own(moved, delivering))).not.toBeNull();
    }
  });

  it('reads a scan without a stage by its wording', () => {
    const relayed = own({ time: '2026-10-17T00:53:23+02:00', description: 'Your parcel is on its way' });
    expect(carrierMovedAt('brt', relayed)).toBe(Date.parse('2026-10-16T22:53:23Z'));
    expect(withoutDisputedDelivery(provider('2026-10-12T01:00:01Z'), 'unknown', 'brt', relayed)).not.toBeNull();
    expect(showsDelivery(own({ local_time: '2026-10-21T10:00:00', description: 'Delivered' }))).toBe(true);
  });

  it('stands when a delivery scan has no date to compare', () => {
    const answer = own({ local_time: '2026-10-21T10:00:00', description: 'In viaggio', stage: 'in_transit' });
    const undated = { ...provider('2026-10-20T18:00:00Z'), events: [{ description: 'Delivered', stage: 'delivered' }] };
    expect(withoutDisputedDelivery(undated, 'unknown', 'brt', answer)).toBeNull();
  });
});
