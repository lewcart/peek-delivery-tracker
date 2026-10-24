-- Parcels of one account merge whatever carriers they are filed under, not only an
-- earlier leg with Swiss Post's: is_later_leg holds the rule. A check merges them
-- right after it stores news, before that news goes out, and a scan both parcels
-- hold keeps the receipts of either copy, so the merged parcel announces it once.
-- link_package_tracking is otherwise copied from 20261003160000_delivery_emails.sql,
-- auto_link_package_tracking from 20261024090000_automatic_links_swiss_post_numbers.sql.

-- Whether a carrier confirms that one parcel of an account is the later leg of
-- another's shipment, under another carrier: it names the earlier leg's number as
-- the item's international number; the earlier leg was handed over to it under a
-- number it gives the item (international or domestic); or the earlier carrier
-- names it as its delivery partner, under one of its numbers. The later leg is not
-- merged yet and has a scan of its own, so its pre-advice never replaces the
-- earlier leg's progress. Carrier references are populated only by server adapters
-- after verifying the requested shipment: never infer identity from labels,
-- senders or number prefixes.
create function public.is_later_leg(original public.packages, delivery public.packages)
returns boolean
language sql
stable
set search_path = pg_catalog
as $$
  select coalesce(delivery.user_id = original.user_id
    and delivery.carrier <> original.carrier
    and delivery.archived_at is null
    and not (delivery.carrier_data ? 'original_carrier')
    and delivery.current_stage not in ('pending', 'registered')
    and ((delivery.carrier_data->>'international_tracking_number' ~ '^[A-Z0-9]{4,40}$'
        and delivery.carrier_data->>'international_tracking_number' = coalesce(
          nullif(original.carrier_data->>'original_canonical_tracking_number', ''),
          case when original.carrier_data->>'active_tracking_carrier' is distinct from delivery.carrier
            then nullif(original.carrier_data->>'canonical_tracking_number', '') end,
          original.tracking_number))
      or (original.carrier_data->>'active_tracking_carrier' = delivery.carrier
        and array[nullif(original.carrier_data->>'active_tracking_number', ''),
          nullif(original.carrier_data->>'canonical_tracking_number', '')]
          && array[delivery.tracking_number,
            nullif(delivery.carrier_data->>'canonical_tracking_number', ''),
            nullif(delivery.carrier_data->>'international_tracking_number', '')])
      or (original.carrier_data->>'delivery_carrier' = delivery.carrier
        and nullif(original.carrier_data->>'delivery_tracking_number', '') in (delivery.tracking_number,
          delivery.carrier_data->>'canonical_tracking_number',
          delivery.carrier_data->>'international_tracking_number'))), false);
$$;

revoke all on function public.is_later_leg(public.packages, public.packages) from public, anon, authenticated;
grant execute on function public.is_later_leg(public.packages, public.packages) to service_role;

create or replace function public.link_package_tracking(p_original_id uuid, p_delivery_id uuid)
returns uuid
language plpgsql
set search_path = pg_catalog
as $$
declare
  original public.packages;
  delivery public.packages;
  combined_label text;
begin
  if p_original_id = p_delivery_id then
    raise exception 'Choose two different parcels' using errcode = '22023';
  end if;
  perform id from public.sync_jobs where package_id in (p_original_id, p_delivery_id) order by id for update;
  perform id from public.packages where id in (p_original_id, p_delivery_id) order by id for update;
  select * into original from public.packages where id = p_original_id;
  select * into delivery from public.packages where id = p_delivery_id;
  if original.id is null and delivery.carrier_data->>'original_package_id' = p_original_id::text then
    return p_delivery_id; -- Safe retry after a completed link.
  end if;
  if original.id is null or delivery.id is null then
    raise exception 'Parcel not found' using errcode = '22023';
  end if;
  if original.user_id is distinct from delivery.user_id or original.user_id is null then
    raise exception 'Parcels must belong to the same account' using errcode = '22023';
  end if;
  if original.carrier_data ? 'original_package_id'
    or (original.carrier_data ? 'original_carrier' and original.carrier_data->>'original_carrier' <> original.carrier)
    or delivery.carrier_data ? 'original_carrier' then
    raise exception 'Parcel already has linked tracking' using errcode = '22023';
  end if;
  combined_label := concat_ws(' / ', nullif(btrim(original.label), ''), nullif(btrim(delivery.label), ''));
  if char_length(combined_label) > 80 then
    raise exception 'Combined parcel name exceeds 80 characters' using errcode = '22023';
  end if;

  -- Keep the delivery carrier's copy of an event if both trackers supplied it, with
  -- the receipts of either copy, so no channel announces the scan a second time.
  insert into public.push_deliveries (subscription_id, event_id, sent_at)
  select receipt.subscription_id, later.id, receipt.sent_at
  from public.tracking_events earlier
  join public.tracking_events later on later.package_id = p_delivery_id
    and later.provider_event_id = earlier.provider_event_id
  join public.push_deliveries receipt on receipt.event_id = earlier.id
  where earlier.package_id = p_original_id
  on conflict (subscription_id, event_id) do nothing;
  insert into public.native_push_deliveries (device_id, event_id, sent_at)
  select receipt.device_id, later.id, receipt.sent_at
  from public.tracking_events earlier
  join public.tracking_events later on later.package_id = p_delivery_id
    and later.provider_event_id = earlier.provider_event_id
  join public.native_push_deliveries receipt on receipt.event_id = earlier.id
  where earlier.package_id = p_original_id
  on conflict (device_id, event_id) do nothing;
  insert into public.parcel_link_alert_deliveries (alert_id, event_id, sent_at)
  select receipt.alert_id, later.id, receipt.sent_at
  from public.tracking_events earlier
  join public.tracking_events later on later.package_id = p_delivery_id
    and later.provider_event_id = earlier.provider_event_id
  join public.parcel_link_alert_deliveries receipt on receipt.event_id = earlier.id
  where earlier.package_id = p_original_id
  on conflict (alert_id, event_id) do nothing;
  delete from public.tracking_events earlier
  using public.tracking_events later
  where earlier.package_id = p_original_id and later.package_id = p_delivery_id
    and earlier.provider_event_id = later.provider_event_id;
  update public.tracking_events set package_id = p_delivery_id where package_id = p_original_id;

  update public.packages set
    label = combined_label,
    created_at = least(original.created_at, delivery.created_at),
    notifications_muted = original.notifications_muted or delivery.notifications_muted,
    email_muted = original.email_muted or delivery.email_muted,
    tracking_generation = gen_random_uuid(),
    carrier_data = coalesce(delivery.carrier_data, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'original_package_id', original.id,
      'original_carrier', original.carrier,
      'original_tracking_number', original.tracking_number,
      'original_tracking_url', original.tracking_url,
      'active_tracking_carrier', delivery.carrier,
      'active_tracking_number', delivery.tracking_number,
      'sender_name', coalesce(original.carrier_data->>'sender_name', delivery.carrier_data->>'sender_name')
    ))
  where id = p_delivery_id;
  update public.sync_jobs set package_id = p_delivery_id where package_id = p_original_id;
  update public.tracking_sync_attempts set package_id = p_delivery_id where package_id = p_original_id;
  update public.delivery_emails set package_id = p_delivery_id
  where package_id = p_original_id
    and not exists (select 1 from public.delivery_emails where package_id = p_delivery_id);
  delete from public.parcel_link_alerts as alert
  using public.parcel_links as stopping
  where alert.link_id = stopping.id
    and stopping.package_id = p_original_id and stopping.created_by is not null and stopping.shared
    and exists (
      select 1 from public.parcel_links as kept
      where kept.package_id = p_delivery_id and kept.created_by = stopping.created_by and kept.shared
    );
  update public.parcel_links as stopping set shared = false, stopped_at = now()
  where stopping.package_id = p_original_id and stopping.created_by is not null and stopping.shared
    and exists (
      select 1 from public.parcel_links as kept
      where kept.package_id = p_delivery_id and kept.created_by = stopping.created_by and kept.shared
    );
  update public.parcel_links set package_id = p_delivery_id where package_id = p_original_id;
  delete from public.packages where id = p_original_id;
  return p_delivery_id;
end;
$$;

create or replace function public.auto_link_package_tracking(p_user_id uuid default null)
returns integer
language plpgsql
set search_path = pg_catalog
as $$
declare
  pair record;
  linked_count integer := 0;
begin
  -- Reconciliation is brief and serial; tracking requests remain concurrent.
  perform pg_advisory_xact_lock(846120260910);
  for pair in
    with matches as (
      select original.id as original_id, delivery.id as delivery_id,
        count(*) over (partition by original.id) as delivery_matches,
        count(*) over (partition by delivery.id) as original_matches
      from public.packages original
      join public.packages delivery on delivery.user_id = original.user_id
        and delivery.id <> original.id
        and public.is_later_leg(original, delivery)
        -- Two parcels that each name the other leave which leg came later open.
        and not public.is_later_leg(delivery, original)
      where original.archived_at is null
        and (not (original.carrier_data ? 'original_package_id')
          and (not (original.carrier_data ? 'original_carrier') or original.carrier_data->>'original_carrier' = original.carrier))
        and (p_user_id is null or original.user_id = p_user_id)
    )
    select * from matches where delivery_matches = 1 and original_matches = 1
    order by original_id, delivery_id
  loop
    -- Lock jobs before packages, matching the worker's lease-write lock order.
    perform id from public.sync_jobs where package_id in (pair.original_id, pair.delivery_id) order by id for update;
    perform id from public.packages where id in (pair.original_id, pair.delivery_id) order by id for update;
    -- A carrier edit, archive, manual link or deletion may have raced selection.
    if exists (
      select 1 from public.packages original join public.packages delivery
        on original.user_id = delivery.user_id
      where original.id = pair.original_id and delivery.id = pair.delivery_id
        and original.archived_at is null
        and (not (original.carrier_data ? 'original_package_id')
          and (not (original.carrier_data ? 'original_carrier') or original.carrier_data->>'original_carrier' = original.carrier))
        and public.is_later_leg(original, delivery) and not public.is_later_leg(delivery, original)
        and char_length(concat_ws(' / ', nullif(btrim(original.label), ''), nullif(btrim(delivery.label), ''))) <= 80
    ) then
      perform public.link_package_tracking(pair.original_id, pair.delivery_id);
      linked_count := linked_count + 1;
    end if;
  end loop;
  return linked_count;
end;
$$;

revoke all on function public.auto_link_package_tracking(uuid) from public, anon, authenticated;
grant execute on function public.auto_link_package_tracking(uuid) to service_role;
revoke all on function public.link_package_tracking(uuid, uuid) from public, anon, authenticated;
grant execute on function public.link_package_tracking(uuid, uuid) to service_role;
notify pgrst, 'reload schema';

insert into public.applied_migrations (name) values ('20261024120000_generic_automatic_links') on conflict do nothing;
