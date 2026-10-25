\set ON_ERROR_STOP on
begin;
-- A delivery-day activity starts once per stretch out for delivery. A scan in no stage
-- (`pending`), a carrier's notice during the round, starts no new stretch; a scan in
-- another stage does.
insert into auth.users(id, email) values ('98000000-0000-0000-0000-000000000001', 'notices@example.invalid');
insert into auth.sessions(id, user_id) values ('98000000-0000-0000-0000-000000000002', '98000000-0000-0000-0000-000000000001');
set local role service_role;
insert into public.live_activity_devices(id, user_id, session_id, installation_id, token, environment, subscribed_at)
values ('98000000-0000-0000-0000-000000000003', '98000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000002', '98000000-0000-0000-0000-000000000004', repeat('cd', 32), 'development',
  '2026-10-01T00:00:00Z');
insert into public.packages(id, user_id, tracking_number, label, carrier, current_stage, carrier_data)
values ('98000000-0000-0000-0000-000000000005', '98000000-0000-0000-0000-000000000001', 'NOTICETEST1', 'Notices',
  'posti', 'out_for_delivery', '{}');
insert into public.tracking_events(id, package_id, stage, description, provider_event_id, occurred_at, created_at, raw_data)
values ('98000000-0000-0000-0000-000000000006', '98000000-0000-0000-0000-000000000005', 'out_for_delivery',
  'Out for delivery', 'posti:out', '2026-10-08T08:40:00Z', '2026-10-08T08:45:00Z', '{}');
insert into public.live_activity_event_deliveries(device_id, event_id, package_id, delivery_kind, event_created_at)
values ('98000000-0000-0000-0000-000000000003', '98000000-0000-0000-0000-000000000006',
  '98000000-0000-0000-0000-000000000005', 'start', '2026-10-08T08:45:00Z');
-- The reader ended the activity. The carrier sends a notice no rule gives a stage, then tells more of the round.
insert into public.tracking_events(id, package_id, stage, description, provider_event_id, occurred_at, created_at, raw_data)
values ('98000000-0000-0000-0000-000000000007', '98000000-0000-0000-0000-000000000005', 'pending',
  'Fixture notice 7', 'posti:notice', '2026-10-08T08:50:00Z', '2026-10-08T08:55:00Z', '{"stage_source": "none"}'),
 ('98000000-0000-0000-0000-000000000008', '98000000-0000-0000-0000-000000000005', 'out_for_delivery',
  'Two stops away', 'posti:stops', '2026-10-08T09:00:00Z', '2026-10-08T09:05:00Z', '{}');
do $$ begin
  if exists (select 1 from public.pending_live_activity_events
             where event_id in ('98000000-0000-0000-0000-000000000007', '98000000-0000-0000-0000-000000000008')) then
    raise exception 'A notice in no stage let a second Live Activity start';
  end if;
end; $$;
-- A scan in another stage between the two is a new stretch.
update public.tracking_events set stage = 'in_transit' where id = '98000000-0000-0000-0000-000000000007';
do $$ begin
  if not exists (select 1 from public.pending_live_activity_events where event_id = '98000000-0000-0000-0000-000000000008') then
    raise exception 'A scan in another stage did not start a new stretch';
  end if;
  if exists (select 1 from public.pending_live_activity_events where event_id = '98000000-0000-0000-0000-000000000007') then
    raise exception 'A scan in another stage started a Live Activity';
  end if;
end; $$;
reset role;
rollback;
