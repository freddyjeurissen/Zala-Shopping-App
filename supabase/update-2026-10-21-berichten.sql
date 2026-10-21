-- Zala - Boodschappen App – update 21-10-2026: berichten per rit
-- Uitvoeren in Supabase: SQL Editor > New query > plak dit bestand > Run. Veilig om vaker te draaien.
-- Gesprekken staan in coll 'rides/<rit-id>/chat/<meerijder-uid>'.
-- Alleen de bestuurder van die rit en die ene meerijder kunnen ze lezen en schrijven.

create or replace function public.ride_chat_party(p_coll text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  uid   text := (auth.uid())::text;
  rid   text;
  rider text;
  r     jsonb;
begin
  if uid is null or p_coll !~ '^rides/[^/]+/chat/[^/]+$' then return false; end if;
  rid   := split_part(p_coll, '/', 2);
  rider := split_part(p_coll, '/', 4);
  select data into r from public.docs where coll = 'rides' and id = rid;
  if r is null then return false; end if;
  -- de meerijder moet bij de rit horen (aangevraagd of bevestigd)
  if not exists (select 1 from jsonb_array_elements(coalesce(r->'riders', '[]'::jsonb)) x where x->>'u' = rider) then
    return false;
  end if;
  return uid = rider or uid = r->>'driver';
end;
$$;

revoke all on function public.ride_chat_party(text) from public, anon;
grant execute on function public.ride_chat_party(text) to authenticated;

drop policy if exists chat_read   on public.docs;
drop policy if exists chat_insert on public.docs;

create policy chat_read on public.docs for select to authenticated
  using (coll ~ '^rides/[^/]+/chat/[^/]+$' and public.ride_chat_party(coll));
create policy chat_insert on public.docs for insert to authenticated
  with check (coll ~ '^rides/[^/]+/chat/[^/]+$' and public.ride_chat_party(coll)
              and data->>'from' = (auth.uid())::text
              and length(coalesce(data->>'val', '')) <= 500);
-- Berichten kunnen niet worden gewijzigd of verwijderd door gebruikers (geen update/delete-policy).
