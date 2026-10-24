\set ON_ERROR_STOP on
begin;
-- A delivery-day activity starts once per stretch out for delivery. A provider's
-- copy of the carrier's scan, read as another stage, starts no new stretch; the
-- carrier's own scan in another stage, or a provider's step the carrier never
-- shows, does.
insert into auth.users(id, email) values ('97000000-0000-0000-0000-000000000001', 'copies@example.invalid');
insert into auth.sessions(id, user_id) values ('97000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000001');
set local role service_role;
insert into public.live_activity_devices(id, user_id, session_id, installation_id, token, environment, subscribed_at)
values ('97000000-0000-0000-0000-000000000003', '97000000-0000-0000-0000-000000000001',
  '97000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000004', repeat('ab', 32), 'development',
  '2026-10-01T00:00:00Z');
insert into public.packages(id, user_id, tracking_number, label, carrier, current_stage, carrier_data)
values ('97000000-0000-0000-0000-000000000005', '97000000-0000-0000-0000-000000000001', 'COPYTEST1', 'Copies',
  'posti', 'out_for_delivery', '{"routing": {"confirmed_carrier": "posti"}}');
insert into public.tracking_events(id, package_id, stage, description, provider_event_id, occurred_at, created_at, raw_data)
values ('97000000-0000-0000-0000-000000000006', '97000000-0000-0000-0000-000000000005', 'out_for_delivery',
  'Out for delivery', 'posti:out', '2026-10-08T08:40:00Z', '2026-10-08T08:45:00Z', '{}');
insert into public.live_activity_event_deliveries(device_id, event_id, package_id, delivery_kind, event_created_at)
values ('97000000-0000-0000-0000-000000000003', '97000000-0000-0000-0000-000000000006',
  '97000000-0000-0000-0000-000000000005', 'start', '2026-10-08T08:45:00Z');
-- 17TRACK stores the scan again, in its own words and stage, then the carrier tells more of the round.
insert into public.tracking_events(id, package_id, stage, description, provider_event_id, occurred_at, created_at, raw_data)
values ('97000000-0000-0000-0000-000000000007', '97000000-0000-0000-0000-000000000005', 'in_transit',
  'Arrived at delivery facility', 'unknown:copy', '2026-10-08T08:40:21Z', '2026-10-08T08:50:00Z',
  '{"universal_provider": "17TRACK"}'),
 ('97000000-0000-0000-0000-000000000008', '97000000-0000-0000-0000-000000000005', 'out_for_delivery',
  'Two stops away', 'posti:stops', '2026-10-08T09:00:00Z', '2026-10-08T09:05:00Z', '{}');
do $$ begin
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'A provider copy at the minute of the carrier''s scan was not hidden';
  end if;
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000006') then
    raise exception 'The carrier''s own scan counted as a provider copy';
  end if;
  if exists (select 1 from public.pending_live_activity_events where event_id = '97000000-0000-0000-0000-000000000008') then
    raise exception 'A provider copy in another stage let a second Live Activity start';
  end if;
end; $$;
-- Without a confirmed carrier, the timeline shows the provider's row, and it starts a new stretch.
update public.packages set carrier_data = '{}' where id = '97000000-0000-0000-0000-000000000005';
do $$ begin
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'A provider row was hidden on a parcel with no confirmed carrier';
  end if;
  if not exists (select 1 from public.pending_live_activity_events where event_id = '97000000-0000-0000-0000-000000000008') then
    raise exception 'A shown provider row in another stage did not start a new stretch';
  end if;
end; $$;
update public.packages set carrier_data = '{"routing": {"confirmed_carrier": "posti"}}'
where id = '97000000-0000-0000-0000-000000000005';
-- A provider's step hours from any carrier scan, in another stage, is no copy: it starts a new stretch.
update public.tracking_events set occurred_at = '2026-10-08T06:07:00Z' where id = '97000000-0000-0000-0000-000000000007';
do $$ begin
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'A provider step the carrier never shows was hidden';
  end if;
  if not exists (select 1 from public.pending_live_activity_events where event_id = '97000000-0000-0000-0000-000000000008') then
    raise exception 'A provider step the carrier never shows did not start a new stretch';
  end if;
end; $$;
-- A copy whole hours off in the carrier scan's stage is hidden; an unnamed universal row only inside
-- the time the carrier's answers covered, and never one they held.
update public.tracking_events set stage = 'out_for_delivery', occurred_at = '2026-10-08T10:40:00Z',
  raw_data = '{}' where id = '97000000-0000-0000-0000-000000000007';
update public.packages set carrier_data = '{"routing": {"confirmed_carrier": "posti"},
  "direct_history": {"from": "2026-10-08T08:00:00Z", "to": "2026-10-08T12:00:00Z", "held": []}}'
where id = '97000000-0000-0000-0000-000000000005';
do $$ begin
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'An unnamed copy two hours off inside the carrier''s time was not hidden';
  end if;
end; $$;
update public.packages set carrier_data = jsonb_set(carrier_data, '{direct_history,held}', '["unknown:copy"]')
where id = '97000000-0000-0000-0000-000000000005';
do $$ begin
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'A row a carrier''s answer held was hidden';
  end if;
end; $$;
-- A copy of a scan dated by its day, on a wall clock in no zone: in its stage and words, whole quarter hours off.
update public.packages set carrier_data = '{"routing": {"confirmed_carrier": "posti"}}'
where id = '97000000-0000-0000-0000-000000000005';
update public.tracking_events set occurred_at = '2026-10-08T00:00:00Z', stage = 'in_transit', description = 'Departed hub',
  raw_data = '{"local_time": "2026-10-08T14:20"}' where id = '97000000-0000-0000-0000-000000000006';
update public.tracking_events set occurred_at = '2026-10-08T06:20:41Z', stage = 'in_transit', description = 'Departed  Hub',
  raw_data = '{"universal_provider": "ParcelsApp"}' where id = '97000000-0000-0000-0000-000000000007';
do $$ begin
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'A copy showing a day-dated scan''s wall clock was not hidden';
  end if;
end; $$;
update public.tracking_events set occurred_at = '2026-10-08T06:27:00Z' where id = '97000000-0000-0000-0000-000000000007';
do $$ begin
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'A row showing another wall clock than the day-dated scan''s was hidden';
  end if;
  if has_function_privilege('authenticated', 'public.hidden_provider_copy(uuid)', 'execute') then
    raise exception 'Clients can run hidden_provider_copy';
  end if;
end; $$;
-- A provider reading the carrier's scans a zone away tells every scan of that minute on the same clock: its other
-- rows of the minute of a copy only whole hours from the carrier's scans are copies too, in any stage.
update public.tracking_events set occurred_at = '2026-10-08T08:40:00Z', stage = 'in_transit',
  description = 'The consignment has left the border point', raw_data = '{}' where id = '97000000-0000-0000-0000-000000000006';
update public.tracking_events set occurred_at = '2026-10-08T09:40:00Z', stage = 'in_transit',
  description = 'Departure from office of exchange', raw_data = '{"universal_provider": "ParcelsApp"}'
where id = '97000000-0000-0000-0000-000000000007';
insert into public.tracking_events(id, package_id, stage, description, provider_event_id, occurred_at, created_at, raw_data)
values ('97000000-0000-0000-0000-000000000009', '97000000-0000-0000-0000-000000000005', 'pending',
  'Item has passed a checkpoint', 'unknown:checkpoint', '2026-10-08T09:40:00Z', '2026-10-08T09:50:00Z',
  '{"universal_provider": "ParcelsApp"}'),
 ('97000000-0000-0000-0000-000000000010', '97000000-0000-0000-0000-000000000005', 'customs',
  'Customs', 'unknown:other', '2026-10-08T09:40:00Z', '2026-10-08T09:50:00Z', '{"universal_provider": "17TRACK"}');
do $$ begin
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000007')
    or not public.hidden_provider_copy('97000000-0000-0000-0000-000000000009') then
    raise exception 'A provider''s rows of the minute it read a zone away were not hidden';
  end if;
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000010') then
    raise exception 'Another provider''s row of that minute was hidden';
  end if;
end; $$;
-- A copy also close to a carrier's scan keeps the carrier's clock: the provider's other rows of its minute stay.
update public.tracking_events set occurred_at = '2026-10-08T09:35:00Z', stage = 'in_transit'
where id = '97000000-0000-0000-0000-000000000008';
do $$ begin
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000007') then
    raise exception 'A copy close to a carrier scan was not hidden';
  end if;
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000009') then
    raise exception 'A provider row of the minute of a copy on the carrier''s clock was hidden';
  end if;
end; $$;
-- A provider tells some scans on two clocks: its twin of a copy, in the copy's words, place and stage whole hours
-- from it, is the same scan, and so is its row by the shift another of its copies at the same place shows. Each
-- hides the provider's other rows of its minute. A twin 90 minutes away, a row at another place or by another
-- shift stays.
insert into public.packages(id, user_id, tracking_number, label, carrier, current_stage, carrier_data)
values ('97000000-0000-0000-0000-000000000011', '97000000-0000-0000-0000-000000000001', 'COPYTEST2', 'Clocks',
  'posti', 'in_transit', '{"routing": {"confirmed_carrier": "posti"}}');
insert into public.tracking_events(id, package_id, stage, description, location, provider_event_id, occurred_at, created_at, raw_data)
values
 ('97000000-0000-0000-0000-000000000012', '97000000-0000-0000-0000-000000000011', 'in_transit', 'Dispatched', 'Origin',
  'posti:dispatched', '2026-10-08T00:12:00Z', '2026-10-09T00:00:00Z', '{}'),
 ('97000000-0000-0000-0000-000000000013', '97000000-0000-0000-0000-000000000011', 'in_transit', 'Ready to leave', 'Airport',
  'posti:ready', '2026-10-08T14:18:00Z', '2026-10-09T00:00:00Z', '{}'),
 ('97000000-0000-0000-0000-000000000014', '97000000-0000-0000-0000-000000000011', 'in_transit', 'Left the country', 'Airport',
  'posti:left', '2026-10-08T23:28:00Z', '2026-10-09T00:00:00Z', '{}'),
 ('97000000-0000-0000-0000-000000000015', '97000000-0000-0000-0000-000000000011', 'accepted', 'Posting', 'Office 1',
  'unknown:posting', '2026-10-08T00:12:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "ParcelsApp"}'),
 ('97000000-0000-0000-0000-000000000016', '97000000-0000-0000-0000-000000000011', 'accepted', 'Posting', 'Office 1',
  'unknown:posting-twin', '2026-10-07T21:12:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "ParcelsApp"}'),
 ('97000000-0000-0000-0000-000000000017', '97000000-0000-0000-0000-000000000011', 'accepted', 'Item posted', 'Country',
  'unknown:posted', '2026-10-07T21:12:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "ParcelsApp"}'),
 ('97000000-0000-0000-0000-000000000018', '97000000-0000-0000-0000-000000000011', 'accepted', 'Posting', 'Office 1',
  'unknown:posting-later', '2026-10-07T22:42:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "ParcelsApp"}'),
 ('97000000-0000-0000-0000-000000000019', '97000000-0000-0000-0000-000000000011', 'in_transit', 'In transfer', 'Origin country',
  'unknown:transfer', '2026-10-08T20:28:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "17TRACK"}'),
 ('97000000-0000-0000-0000-000000000020', '97000000-0000-0000-0000-000000000011', 'registered', 'Received at export', 'Origin country',
  'unknown:export', '2026-10-08T11:18:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "17TRACK"}'),
 ('97000000-0000-0000-0000-000000000021', '97000000-0000-0000-0000-000000000011', 'registered', 'Received at export', 'Other country',
  'unknown:export-elsewhere', '2026-10-07T21:12:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "17TRACK"}'),
 ('97000000-0000-0000-0000-000000000022', '97000000-0000-0000-0000-000000000011', 'registered', 'Received at export', 'Origin country',
  'unknown:export-shift', '2026-10-08T12:18:00Z', '2026-10-09T00:00:00Z', '{"universal_provider": "17TRACK"}');
do $$ begin
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000015')
    or not public.hidden_provider_copy('97000000-0000-0000-0000-000000000019') then
    raise exception 'A provider copy of a carrier scan was not hidden';
  end if;
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000016') then
    raise exception 'A provider''s twin of its copy, whole hours away, was not hidden';
  end if;
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000017') then
    raise exception 'A provider''s row of the minute of its twin was not hidden';
  end if;
  if not public.hidden_provider_copy('97000000-0000-0000-0000-000000000020') then
    raise exception 'A provider row at the shift of its copy at the same place was not hidden';
  end if;
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000018') then
    raise exception 'A provider row 90 minutes from its copy was hidden as a twin';
  end if;
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000021') then
    raise exception 'A provider row at another place than its shifted copy was hidden';
  end if;
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000022') then
    raise exception 'A provider row at another shift than its copy at the same place was hidden';
  end if;
  if public.hidden_provider_copy('97000000-0000-0000-0000-000000000012') then
    raise exception 'The carrier''s own scan counted as a provider copy';
  end if;
end; $$;
reset role;
rollback;
