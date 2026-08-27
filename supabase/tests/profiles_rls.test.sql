\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', 'a@nexo.test', '{"full_name":"Perfil A"}'),
  ('22222222-2222-2222-2222-222222222222', 'b@nexo.test', '{"full_name":"Perfil B"}');

do $$
begin
  if (select count(*) from public.profiles) <> 2 then
    raise exception 'profile trigger did not create one profile per auth user';
  end if;
  if (select count(*) from public.currencies where code in ('MXN', 'USD', 'EUR')) <> 3 then
    raise exception 'required currency seed is incomplete';
  end if;
  if has_table_privilege('anon', 'public.profiles', 'select') then
    raise exception 'anon unexpectedly has profile select privilege';
  end if;
  if has_table_privilege('authenticated', 'public.profiles', 'insert') then
    raise exception 'authenticated unexpectedly has profile insert privilege';
  end if;
  if has_table_privilege('authenticated', 'public.profiles', 'delete') then
    raise exception 'authenticated unexpectedly has profile delete privilege';
  end if;
  if has_column_privilege('authenticated', 'public.profiles', 'created_at', 'update') then
    raise exception 'authenticated unexpectedly updates immutable profile timestamps';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

do $$
declare
  visible_profiles integer;
  updated_profiles integer;
begin
  select count(*) into visible_profiles from public.profiles;
  if visible_profiles <> 1 then
    raise exception 'RLS user A expected 1 visible profile, got %', visible_profiles;
  end if;

  update public.profiles
  set full_name = 'Perfil A actualizado', base_currency = 'USD', timezone = 'America/Mexico_City'
  where id = '11111111-1111-1111-1111-111111111111';
  get diagnostics updated_profiles = row_count;
  if updated_profiles <> 1 then
    raise exception 'user A could not update own profile';
  end if;

  update public.profiles
  set full_name = 'Ataque cruzado'
  where id = '22222222-2222-2222-2222-222222222222';
  get diagnostics updated_profiles = row_count;
  if updated_profiles <> 0 then
    raise exception 'RLS allowed user A to update user B';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

do $$
declare
  own_name text;
begin
  select full_name into own_name from public.profiles;
  if own_name <> 'Perfil B' then
    raise exception 'user B observed another profile';
  end if;
end;
$$;

reset role;
set local role anon;

do $$
begin
  if (select count(*) from public.currencies) <> 3 then
    raise exception 'anon cannot read the public currency catalogue';
  end if;
  if has_table_privilege('anon', 'public.currencies', 'insert') then
    raise exception 'anon unexpectedly writes currencies';
  end if;
end;
$$;

reset role;
rollback;

select 'profiles RLS tests passed' as result;
