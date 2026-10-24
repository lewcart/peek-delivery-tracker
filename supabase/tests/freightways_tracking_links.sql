\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email) values ('19000000-0000-0000-0000-000000000050', 'freightways-links-test@example.test');
select set_config('request.jwt.claim.sub', '19000000-0000-0000-0000-000000000050', true);
set local role authenticated;
do $$
declare
  parcel public.packages;
  -- Synthetic consignment numbers and sender's account.
  composite text := 'https://receiver.nzcouriers.co.nz/?consignmentid=CU..ZZZZ047193.Z.0000000.1';
  customer_label text := 'https://receiver.posthaste.co.nz/?request_id=3&customer_number=0000000&consignment_id=ZZZZ047194';
begin
  parcel := test_support.add_parcel('ZZZZ047193', 'Freightways fixture', 'nz-couriers', composite);
  if parcel.tracking_url <> composite then raise exception 'The receiver link was not saved'; end if;
  parcel := test_support.add_parcel('ZZZZ047194', 'Freightways without link', 'post-haste');
  if parcel.tracking_url is not null then raise exception 'Post Haste invented a tracking link'; end if;
  perform public.change_owned_package_carrier(parcel.id, 'post-haste', customer_label);
  if (select tracking_url from public.packages where id = parcel.id) <> customer_label then
    raise exception 'The customer label link was not saved';
  end if;
  perform public.change_owned_package_carrier(parcel.id, 'castle-parcels',
    'https://receiver.castleparcels.co.nz/?consignmentid=CU..ZZZZ047194.Z.0000000.12');
  perform public.change_owned_package_carrier(parcel.id, 'now-couriers',
    'https://receiver.nowcouriers.co.nz/?request_id=3&customer_number=ZZ00000&consignment_id=ZZZZ047194');
  begin
    perform test_support.add_parcel('ZZZZ047195', 'Another consignment', 'nz-couriers', composite);
    raise exception 'A link for another consignment was accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.change_owned_package_carrier(parcel.id, 'nz-couriers', customer_label);
    raise exception 'A link of another network was accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.change_owned_package_carrier(parcel.id, 'post-haste',
      'https://receiver.posthaste.co.nz/?track=ZZZZ047194');
    raise exception 'A link without the sender''s account was accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.change_owned_package_carrier(parcel.id, 'post-haste', customer_label || '&token=synthetic');
    raise exception 'A link the scraper does not keep was accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.change_owned_package_carrier(parcel.id, 'post-haste',
      'http://receiver.posthaste.co.nz/?request_id=3&customer_number=0000000&consignment_id=ZZZZ047194');
    raise exception 'A plain http link was accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.change_owned_package_carrier(parcel.id, 'nz-post', composite);
    raise exception 'Another carrier took a Freightways link';
  exception when sqlstate '22023' then null;
  end;
  perform public.change_owned_package_carrier(parcel.id, 'nz-post');
  if (select tracking_url from public.packages where id = parcel.id) is not null then
    raise exception 'The Freightways link followed the parcel to another carrier';
  end if;
end;
$$;
reset role;
-- The table refuses a link the functions refuse.
do $$
begin
  update public.packages set tracking_url = 'https://receiver.nzcouriers.co.nz/?consignmentid=CU..ZZZZ000000.Z.0000000.1'
  where tracking_number = 'ZZZZ047193' and carrier = 'nz-couriers';
  raise exception 'The table accepted a link for another consignment';
exception when check_violation then null;
end;
$$;
rollback;
