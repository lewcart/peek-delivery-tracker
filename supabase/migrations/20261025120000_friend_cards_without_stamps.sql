-- The server works out a shared card's counts and stamps from its owner's parcels
-- (withSharedPassports in src/server/friends.ts), so a card's stats here only mark that its
-- owner shares them. The weekly arrival signal is still decided here.
create or replace function private.friend_card(p_owner uuid)
returns jsonb language sql stable security definer set search_path = pg_catalog as $$
  with journeys as (
    select (array_agg(e.stage::text order by e.occurred_at desc,
        case e.stage::text when 'registered' then 0 when 'accepted' then 1 when 'in_transit' then 2
          when 'customs' then 3 when 'out_for_delivery' then 4 when 'failed_attempt' then 5
          when 'ready_for_pickup' then 6 when 'delivered' then 7 when 'returned' then 8 else -1 end desc,
        e.id desc))[1] stage,
      min(e.occurred_at) filter (where e.stage::text = 'delivered') arrived
    from public.tracking_events e join public.packages p on p.id = e.package_id
    where p.user_id = p_owner and e.stage::text <> 'pending'
    group by e.package_id
  )
  select jsonb_build_object(
    'id', f.id, 'nickname', f.nickname,
    'stats', case when f.share_stats then '{"deliveredCount":0,"averageDays":null,"stamps":[]}'::jsonb else null end,
    'arrivedThisWeek', case when f.share_arrival then coalesce((select bool_or(stage = 'delivered'
      and arrived >= date_trunc('week', now() at time zone 'UTC') at time zone 'UTC' and arrived <= now()) from journeys), false)
      else null end
  ) from public.friend_profiles f where f.user_id = p_owner;
$$;
revoke all on function private.friend_card(uuid) from public, anon, authenticated;

drop function private.passport_country(text);

insert into public.applied_migrations (name) values ('20261025120000_friend_cards_without_stamps') on conflict do nothing;
