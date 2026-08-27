-- Nexo Phase 1: identity profile and the read-only currency catalogue.
-- No financial accounts, cards, transactions, receivables, or installments belong here.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

-- New public objects are opt-in for Data API roles. Grants and RLS remain
-- separate controls and are both declared below.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

create table public.currencies (
  code text primary key,
  name text not null,
  symbol text not null,
  minor_unit smallint not null,
  created_at timestamptz not null default now(),
  constraint currencies_code_iso_format check (code ~ '^[A-Z]{3}$'),
  constraint currencies_name_not_blank check (char_length(btrim(name)) between 1 and 80),
  constraint currencies_symbol_not_blank check (char_length(btrim(symbol)) between 1 and 8),
  constraint currencies_minor_unit_range check (minor_unit between 0 and 6)
);

comment on table public.currencies is
  'Read-only ISO currency catalogue. Nexo does not perform automatic FX in the MVP.';

insert into public.currencies (code, name, symbol, minor_unit)
values
  ('MXN', 'Peso mexicano', '$', 2),
  ('USD', 'Dólar estadounidense', '$', 2),
  ('EUR', 'Euro', '€', 2);

alter table public.currencies enable row level security;

revoke all on table public.currencies from anon, authenticated;
grant select on table public.currencies to anon, authenticated;
grant all on table public.currencies to service_role;

create policy "Currencies are readable"
on public.currencies
for select
to anon, authenticated
using (true);

create function private.is_valid_timezone(candidate text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = candidate
  )
$$;

revoke all on function private.is_valid_timezone(text) from public, anon, authenticated;
grant execute on function private.is_valid_timezone(text) to authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  base_currency text not null default 'MXN' references public.currencies (code),
  timezone text not null default 'UTC',
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_full_name_length check (char_length(full_name) <= 120),
  constraint profiles_timezone_length check (char_length(btrim(timezone)) between 1 and 100),
  constraint profiles_timezone_is_iana check (private.is_valid_timezone(timezone))
);

comment on table public.profiles is
  'One-to-one application profile for auth.users. Authorization never trusts user metadata.';

alter table public.profiles enable row level security;

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (full_name, base_currency, timezone, onboarding_completed)
  on table public.profiles to authenticated;
grant all on table public.profiles to service_role;

create policy "Users can read their own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

create policy "Users can update their own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function private.set_updated_at();

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  safe_full_name text;
begin
  safe_full_name := left(
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), ''),
    120
  );

  insert into public.profiles (id, full_name, base_currency, timezone)
  values (new.id, safe_full_name, 'MXN', 'UTC')
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function private.handle_new_user();
