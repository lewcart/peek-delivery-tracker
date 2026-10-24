-- A parcel already handed over to Swiss Post merges with a Swiss Post parcel of the
-- same account under any number Swiss Post gave the item: the number it was handed
-- over under (often the international one), the domestic number Swiss Post's later
-- answers add, and on the other parcel its own, domestic or international number.
-- Before, only the handed-over number was compared with the other parcel's own, so
-- a parcel added under Swiss Post's domestic number stayed apart. Everything else
-- is copied from 20260912120000_carrier_handoff_links.sql.
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
        and delivery.carrier = 'swiss-post'
        and delivery.archived_at is null
        and not (delivery.carrier_data ? 'original_carrier')
        and delivery.current_stage not in ('pending', 'registered')
        and ((delivery.carrier_data->>'international_tracking_number' ~ '^[A-Z0-9]{4,40}$'
          and delivery.carrier_data->>'international_tracking_number' = coalesce(
            nullif(original.carrier_data->>'original_canonical_tracking_number', ''),
            case when original.carrier_data->>'active_tracking_carrier' is distinct from 'swiss-post'
              then nullif(original.carrier_data->>'canonical_tracking_number', '') end,
            original.tracking_number))
          or (original.carrier_data->>'active_tracking_carrier' = 'swiss-post'
            and array[nullif(original.carrier_data->>'active_tracking_number', ''),
              nullif(original.carrier_data->>'canonical_tracking_number', '')]
              && array[delivery.tracking_number,
                nullif(delivery.carrier_data->>'canonical_tracking_number', ''),
                nullif(delivery.carrier_data->>'international_tracking_number', '')]))
      where original.carrier <> 'swiss-post'
        and original.archived_at is null
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
        and original.carrier <> 'swiss-post' and delivery.carrier = 'swiss-post'
        and original.archived_at is null and delivery.archived_at is null
        and (not (original.carrier_data ? 'original_package_id')
          and (not (original.carrier_data ? 'original_carrier') or original.carrier_data->>'original_carrier' = original.carrier)) and not (delivery.carrier_data ? 'original_carrier')
        and delivery.current_stage not in ('pending', 'registered')
        and ((delivery.carrier_data->>'international_tracking_number' ~ '^[A-Z0-9]{4,40}$'
          and delivery.carrier_data->>'international_tracking_number' = coalesce(
            nullif(original.carrier_data->>'original_canonical_tracking_number', ''),
            case when original.carrier_data->>'active_tracking_carrier' is distinct from 'swiss-post'
              then nullif(original.carrier_data->>'canonical_tracking_number', '') end,
            original.tracking_number))
          or (original.carrier_data->>'active_tracking_carrier' = 'swiss-post'
            and array[nullif(original.carrier_data->>'active_tracking_number', ''),
              nullif(original.carrier_data->>'canonical_tracking_number', '')]
              && array[delivery.tracking_number,
                nullif(delivery.carrier_data->>'canonical_tracking_number', ''),
                nullif(delivery.carrier_data->>'international_tracking_number', '')]))
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
notify pgrst, 'reload schema';

insert into public.applied_migrations (name) values ('20261024090000_automatic_links_swiss_post_numbers') on conflict do nothing;
