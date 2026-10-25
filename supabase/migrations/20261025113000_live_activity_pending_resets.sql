-- A delivery-day activity starts once per stretch out for delivery: another scan
-- of the parcel in another stage starts a new stretch. A scan in no stage
-- (`pending`), such as a carrier's notice to the recipient during the round, is
-- no new stretch either: it moves the parcel neither back nor on, so it no
-- longer lets a second activity start after the reader ended the first.
-- Built on 20261021040000_live_activity_provider_copies.

create or replace view public.pending_live_activity_events
with (security_invoker = true) as
select
  device.id as device_id,
  device.token as push_to_start_token,
  device.environment,
  device.locale,
  update_token.id as update_token_id,
  update_token.activity_id,
  update_token.token as update_token,
  event.id as event_id,
  event.package_id,
  package.label,
  package.carrier,
  package.expected_delivery,
  event.stage,
  event.description,
  event.location,
  event.occurred_at,
  event.created_at as event_created_at,
  coalesce(preference.timezone, 'Europe/Zurich') as timezone,
  (
    event.raw_data -> 'observed_without_provider_timestamp' is distinct from 'true'::jsonb
    and coalesce(event.raw_data ->> 'time' ~ '[T ][0-9]{2}:[0-9]{2}', false)
  ) as event_has_time
from public.live_activity_devices as device
join public.packages as package
  on package.user_id = device.user_id
join public.tracking_events as event
  on event.package_id = package.id
 and event.created_at > device.subscribed_at
 and event.provider_event_id is distinct from 'app:registered'
 and event.provider_event_id is distinct from 'app:pending'
 and event.stage <> 'pending'
left join public.live_activity_update_tokens as update_token
  on update_token.device_id = device.id
 and update_token.package_id = package.id
left join public.live_activity_event_deliveries as delivery
  on delivery.device_id = device.id
 and delivery.event_id = event.id
left join public.notification_preferences as preference
  on preference.user_id = device.user_id
where device.disabled_at is null
  and delivery.event_id is null
  and (
    (
      update_token.id is not null
      and event.created_at >= update_token.started_at
    )
    or (
      update_token.id is null
      and package.archived_at is null
      and package.current_stage = 'out_for_delivery'
      and event.stage = 'out_for_delivery'
      and package.id in (
        select candidate.id
        from public.packages as candidate
        where candidate.user_id = device.user_id
          and candidate.archived_at is null
          and candidate.current_stage = 'out_for_delivery'
        order by
          exists (
            select 1
            from public.live_activity_update_tokens as active_token
            where active_token.device_id = device.id
              and active_token.package_id = candidate.id
          ) desc,
          candidate.expected_delivery asc nulls last,
          (
            select max(candidate_event.occurred_at)
            from public.tracking_events as candidate_event
            where candidate_event.package_id = candidate.id
          ) desc nulls last,
          candidate.label asc,
          candidate.id asc
        limit 2
      )
      and not exists (
        select 1
        from public.live_activity_event_deliveries as prior_delivery
        where prior_delivery.device_id = device.id
          and prior_delivery.package_id = package.id
          and prior_delivery.delivery_kind = 'start'
          and prior_delivery.event_created_at > coalesce(
            (
              select max(reset_event.created_at)
              from public.tracking_events as reset_event
              where reset_event.package_id = package.id
                and reset_event.stage not in ('out_for_delivery', 'pending')
                and reset_event.created_at < event.created_at
                and not public.hidden_provider_copy(reset_event.id)
            ),
            '-infinity'::timestamptz
          )
      )
    )
  );

revoke all on public.pending_live_activity_events from public, anon, authenticated;
grant select on public.pending_live_activity_events to service_role;

notify pgrst, 'reload schema';

insert into public.applied_migrations (name) values ('20261025113000_live_activity_pending_resets') on conflict do nothing;
