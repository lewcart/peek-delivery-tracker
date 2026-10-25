import { classifyStage, inferStage, resultStage, type CarrierResult } from 'universal-parcel-scraper';
import { eventTimestamp, resultTimezone } from 'universal-parcel-scraper/app';
import { STAGES } from '../generated/apiContract';
import { isRecord, type JsonObject } from './types';

/**
 * How long a delivery only a provider reported, which the parcel's own carrier did not
 * show, is checked again (`unconfirmed_delivery_until` in `carrier_data`).
 */
export const UNCONFIRMED_DELIVERY_MS = 3 * 24 * 60 * 60_000;

const FINAL_STAGES = new Set(['delivered', 'returned']);
const VALID_STAGES = new Set<string>(STAGES);

/** A scan's stage: the one its carrier declared, else the one its wording reads as. */
export function eventStage(event: JsonObject): string {
  const declared = String(event.stage ?? '');
  return VALID_STAGES.has(declared) ? declared : inferStage(String(event.description ?? ''));
}

/** The stages a scan read as in transit would step back from. */
const PAST_TRANSIT = new Set(['out_for_delivery', 'delivered', 'ready_for_pickup', 'failed_attempt', 'returned', 'exception']);

/**
 * The stage a scan gives itself: the one its carrier declared, unless the carrier says the scan
 * only keeps the stage of the scan before it (`stage_source` `none`, a notice to the recipient),
 * else the one a wording rule reads it as. Null for a scan in no stage of its own.
 */
function ownStage(event: JsonObject): string | null {
  const declared = String(event.stage ?? '');
  if (VALID_STAGES.has(declared)) return event.stage_source === 'none' ? null : declared;
  const wording = classifyStage(String(event.description ?? ''));
  return wording.source === 'none' ? null : wording.stage;
}

/**
 * The stage each scan of one answer is stored in, given the instant each is dated at (null for
 * a scan with no date): `eventStage`, except for a dated scan in no stage of its own (`ownStage`).
 * That one reads as the stage its carrier left it in, else as in transit, news that the parcel
 * moves, unless that is a step back from the newest dated scan in a stage of its own at or
 * before it (out for delivery, a delivery, a pickup point, a missed attempt, a return or a
 * problem). It is then pending: it stays in the timeline as the carrier's news but moves the
 * parcel neither back nor on (a carrier's notice after the delivery), and its wording never
 * stands for the stage it followed. A scan left pending is in no stage.
 */
export function scanStages(events: readonly JsonObject[], instants: readonly (string | null)[]): string[] {
  const read = events.map(ownStage);
  const times = events.map((_, index) => Date.parse(instants[index] ?? ''));
  return read.map((stage, index) => {
    if (stage !== null) return stage;
    const declared = String(events[index].stage ?? '');
    const kept = VALID_STAGES.has(declared) ? declared : 'in_transit';
    const at = times[index];
    if (!Number.isFinite(at)) return kept;
    let newest = Number.NEGATIVE_INFINITY;
    let past = false;
    for (const [other, otherStage] of read.entries()) {
      const time = times[other];
      if (otherStage === null || otherStage === 'pending' || !Number.isFinite(time) || time > at || time < newest) continue;
      past = (time === newest && past) || PAST_TRANSIT.has(otherStage);
      newest = time;
    }
    return past ? 'pending' : kept;
  });
}

function scanTime(event: JsonObject, zone: string): number {
  return Date.parse(eventTimestamp(event.time || event.local_time, zone) ?? '');
}

/** Whether a carrier's own answer shows the parcel delivered, in its summary or a scan. */
export function showsDelivery(answer: CarrierResult | null): boolean {
  return answer !== null && [answer.status, answer.current_stage, ...(answer.events ?? []).filter(isRecord).map(eventStage)].includes('delivered');
}

/**
 * When a carrier's own answer last moved the parcel, as epoch milliseconds: its newest
 * scan in a stage of its own (`ownStage`), read on the carrier's clock. A scan in none, such as
 * a notice no rule reads, is one `scanStages` stores pending after a delivery, so it moves
 * nothing. NaN when the answer shows a delivery or a return, or no dated scan in a stage: it
 * then disputes no delivery.
 */
export function carrierMovedAt(carrier: string, answer: CarrierResult): number {
  const events = (answer.events ?? []).filter(isRecord);
  if ([answer.status, answer.current_stage, ...events.map(eventStage)].some((stage) => FINAL_STAGES.has(String(stage)))) {
    return Number.NaN;
  }
  const zone = resultTimezone(carrier, answer);
  const times = events.filter((event) => { const stage = ownStage(event); return stage !== null && stage !== 'pending'; })
    .map((event) => scanTime(event, zone)).filter(Number.isFinite);
  return times.length ? Math.max(...times) : Number.NaN;
}

/**
 * A provider's answer without the delivery the parcel's own carrier disputes in the
 * same check: the carrier shows none and moved the parcel at the time of the provider's
 * newest delivery or later. The provider's delivery scans go, and a summary of delivery
 * gives way to the carrier's own. Null when nothing is disputed, as when the carrier's
 * newest scan is older than the delivery or a delivery scan has no date.
 */
export function withoutDisputedDelivery(
  provider: CarrierResult,
  providerSource: string,
  carrier: string,
  answer: CarrierResult,
): CarrierResult | null {
  const moved = carrierMovedAt(carrier, answer);
  if (!Number.isFinite(moved)) return null;
  const zone = resultTimezone(providerSource, provider);
  const events = provider.events ?? [];
  const deliveries = events.filter((event) => eventStage(event) === 'delivered').map((event) => scanTime(event, zone));
  const summary = provider.status === 'delivered' || resultStage(provider) === 'delivered';
  const delivered = deliveries.length ? Math.max(...deliveries) : summary ? scanTime({ time: provider.delivered_at }, zone) : Number.NaN;
  if (deliveries.some((time) => !Number.isFinite(time)) || !Number.isFinite(delivered) || delivered > moved) return null;
  const kept: CarrierResult = { ...provider };
  delete kept.delivered_at;
  return {
    ...kept,
    events: events.filter((event) => eventStage(event) !== 'delivered'),
    ...(summary ? {
      status: answer.status, current_stage: answer.current_stage,
      current_stage_source: answer.current_stage_source, last_status_text: answer.last_status_text,
    } : {}),
  };
}
