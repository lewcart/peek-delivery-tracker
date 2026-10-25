-- A card tells only whether its owner shares stats: the server works out the counts and stamps
-- (withSharedPassports in src/server/friends.ts). The weekly arrival signal is still decided here.
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
    'id', f.id, 'nickname', f.nickname, 'sharesStats', f.share_stats,
    'arrivedThisWeek', case when f.share_arrival then coalesce((select bool_or(stage = 'delivered'
      and arrived >= date_trunc('week', now() at time zone 'UTC') at time zone 'UTC' and arrived <= now()) from journeys), false)
      else null end
  ) from public.friend_profiles f where f.user_id = p_owner;
$$;
revoke all on function private.friend_card(uuid) from public, anon, authenticated;

insert into public.applied_migrations (name) values ('20261025130000_friend_cards_shares_stats_flag') on conflict do nothing;
