-- Nexo Phase 5B correction: contactService.list() was calling
-- get_person_collection_period once per contact from the client (N+1 round
-- trips), and a single missing/failing call there took down the whole list
-- even though contact_balance_summary (the base data: name, total debt) is
-- a separate, independent query. This adds one aggregate view so the list
-- needs exactly one extra round trip regardless of how many contacts exist.
--
-- It does not duplicate the period-selection logic: each row still comes
-- from calling the existing get_person_collection_period function, just
-- once per contact inside a single query plan instead of once per contact
-- from the browser. No balance, schedule or credit computation is
-- reimplemented here.
create view public.contact_period_overview with (security_invoker = true) as
select contact.id as contact_id, contact.user_id,
  coalesce(jsonb_agg(period.value order by period.value ->> 'currency')
    filter (where period.value is not null), '[]'::jsonb) as periods
from public.contacts contact
left join lateral jsonb_array_elements(
  public.get_person_collection_period(contact.id, current_date) -> 'periods'
) as period(value) on true
group by contact.id, contact.user_id;

revoke all on table public.contact_period_overview from anon, authenticated;
grant select on table public.contact_period_overview to authenticated;
grant all on table public.contact_period_overview to service_role;
