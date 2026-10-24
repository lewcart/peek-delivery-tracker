-- A check whose carrier refused the number, or asked for details only the owner can give, failed
-- for its parcel and not for its carrier. It ends `refused`, which the error counts here and in
-- metrics.health leave out, as health incidents already do.
alter table public.tracking_sync_attempts drop constraint tracking_sync_attempts_outcome_check;
alter table public.tracking_sync_attempts add constraint tracking_sync_attempts_outcome_check
  check (outcome in ('running', 'updated', 'unchanged', 'waiting', 'error', 'refused', 'unsupported', 'abandoned',
    'superseded', 'interrupted'));

-- Appends its column: a replaced view keeps the ones it had, in order.
create or replace view public.tracking_sync_health_24h
with (security_invoker = true)
as
select
  configured_carrier,
  count(*) as attempts,
  count(*) filter (where outcome = 'updated') as updated,
  count(*) filter (where outcome = 'waiting') as waiting,
  count(*) filter (where outcome = 'error') as errors,
  count(*) filter (where outcome = 'unsupported') as unsupported,
  count(*) filter (where outcome = 'abandoned') as abandoned,
  count(*) filter (where cardinality(anomaly_codes) > 0) as anomalous,
  round(
    100.0 * count(*) filter (where outcome in ('error', 'abandoned'))
      / nullif(count(*), 0),
    2
  ) as error_percent,
  max(started_at) as last_attempt_at,
  count(*) filter (where outcome = 'unchanged') as unchanged,
  sum(events_new) as events_new,
  count(*) filter (where outcome = 'refused') as refused
from public.tracking_sync_attempts
where started_at >= now() - interval '24 hours'
group by configured_carrier;

insert into public.applied_migrations (name) values ('20261024170000_refused_tracking_checks') on conflict do nothing;
