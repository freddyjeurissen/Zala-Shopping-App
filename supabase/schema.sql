-- Boodschappen Zala – database voor Supabase (Postgres)
-- Uitvoeren in Supabase: SQL Editor > New query > plak dit bestand > Run.
-- Eén tabel met JSON-documenten, beveiligd met Row Level Security per collectie:
--   profiles/<uid>          eigen profiel; leesbaar voor ingelogde gebruikers, schrijven alleen door jezelf
--   hh/<id>                 huishouden; alleen leden lezen en schrijven
--   hh/<id>/items/<id>      boodschappen; alleen leden van dat huishouden
--   rides/<id>              poolauto-ritten; leesbaar voor ingelogde gebruikers, beheer door de bestuurder
-- Lid worden van een huishouden en meerijden aanvragen lopen via functies (RPC) met eigen controles.

create table if not exists public.docs (
  coll        text        not null,
  id          text        not null,
  data        jsonb       not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  primary key (coll, id),
  constraint docs_size check (pg_column_size(data) < 64000)
);
create index if not exists docs_coll_idx on public.docs (coll);

alter table public.docs enable row level security;
alter table public.docs replica identity full;

-- Anoniem (niet ingelogd) mag niets; ingelogd alleen wat de policies toestaan.
revoke all on public.docs from anon;
grant select, insert, update, delete on public.docs to authenticated;

-- Hulpfunctie: is de ingelogde gebruiker lid van huishouden p_hid?
create or replace function public.is_hh_member(p_hid text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.docs
    where coll = 'hh' and id = p_hid
      and coalesce(data->'members', '[]'::jsonb) ? (auth.uid())::text
  );
$$;

-- Policies opnieuw aanmaken (veilig om dit script vaker te draaien)
drop policy if exists profiles_read   on public.docs;
drop policy if exists profiles_write  on public.docs;
drop policy if exists profiles_update on public.docs;
drop policy if exists profiles_delete on public.docs;
drop policy if exists hh_read   on public.docs;
drop policy if exists hh_insert on public.docs;
drop policy if exists hh_update on public.docs;
drop policy if exists items_all on public.docs;
drop policy if exists rides_read   on public.docs;
drop policy if exists rides_insert on public.docs;
drop policy if exists rides_update on public.docs;
drop policy if exists rides_delete on public.docs;

-- Profielen
create policy profiles_read on public.docs for select to authenticated
  using (coll = 'profiles');
create policy profiles_write on public.docs for insert to authenticated
  with check (coll = 'profiles' and id = (auth.uid())::text);
create policy profiles_update on public.docs for update to authenticated
  using (coll = 'profiles' and id = (auth.uid())::text)
  with check (coll = 'profiles' and id = (auth.uid())::text);
create policy profiles_delete on public.docs for delete to authenticated
  using (coll = 'profiles' and id = (auth.uid())::text);

-- Huishoudens: alleen leden. Een lid mag zichzelf eruit halen (vandaar geen lidmaatschapseis in with check).
create policy hh_read on public.docs for select to authenticated
  using (coll = 'hh' and coalesce(data->'members', '[]'::jsonb) ? (auth.uid())::text);
create policy hh_insert on public.docs for insert to authenticated
  with check (coll = 'hh' and coalesce(data->'members', '[]'::jsonb) ? (auth.uid())::text);
create policy hh_update on public.docs for update to authenticated
  using (coll = 'hh' and coalesce(data->'members', '[]'::jsonb) ? (auth.uid())::text)
  with check (coll = 'hh');

-- Boodschappen binnen een huishouden
create policy items_all on public.docs for all to authenticated
  using (coll ~ '^hh/[^/]+/items$' and public.is_hh_member(split_part(coll, '/', 2)))
  with check (coll ~ '^hh/[^/]+/items$' and public.is_hh_member(split_part(coll, '/', 2)));

-- Ritten
create policy rides_read on public.docs for select to authenticated
  using (coll = 'rides');
create policy rides_insert on public.docs for insert to authenticated
  with check (coll = 'rides' and data->>'driver' = (auth.uid())::text);
create policy rides_update on public.docs for update to authenticated
  using (coll = 'rides' and data->>'driver' = (auth.uid())::text)
  with check (coll = 'rides' and data->>'driver' = (auth.uid())::text);
create policy rides_delete on public.docs for delete to authenticated
  using (coll = 'rides' and data->>'driver' = (auth.uid())::text);

-- Velden samenvoegen in een bestaand document (RLS blijft gelden)
create or replace function public.doc_merge(p_coll text, p_id text, p_patch jsonb)
returns void
language plpgsql security invoker set search_path = public
as $$
begin
  update public.docs set data = data || p_patch, updated_at = now()
  where coll = p_coll and id = p_id;
  if not found then
    raise exception 'document niet gevonden of geen toegang' using errcode = '42501';
  end if;
end;
$$;

-- Lid worden van een huishouden met de code
create or replace function public.join_household(p_code text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  uid text := (auth.uid())::text;
  h   record;
begin
  if uid is null then raise exception 'niet ingelogd' using errcode = '42501'; end if;
  if p_code is null or length(trim(p_code)) <> 6 then return null; end if;
  select id, data into h from public.docs
    where coll = 'hh' and data->>'code' = upper(trim(p_code))
    limit 1 for update;
  if not found then return null; end if;
  if not (coalesce(h.data->'members', '[]'::jsonb) ? uid) then
    update public.docs
      set data = jsonb_set(data, '{members}', coalesce(data->'members', '[]'::jsonb) || to_jsonb(uid)),
          updated_at = now()
      where coll = 'hh' and id = h.id;
  end if;
  return jsonb_build_object('id', h.id, 'name', h.data->>'name');
end;
$$;

-- Een huishouden verlaten (jezelf uit de ledenlijst halen)
create or replace function public.leave_household(p_hid text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  uid text := (auth.uid())::text;
begin
  if uid is null then raise exception 'niet ingelogd' using errcode = '42501'; end if;
  update public.docs
    set data = jsonb_set(data, '{members}',
          coalesce((select jsonb_agg(m) from jsonb_array_elements(coalesce(data->'members', '[]'::jsonb)) m
                    where m <> to_jsonb(uid)), '[]'::jsonb)),
        updated_at = now()
    where coll = 'hh' and id = p_hid and coalesce(data->'members', '[]'::jsonb) ? uid;
end;
$$;

-- Meerijden aanvragen ('ask') of de aanvraag intrekken ('cancel')
create or replace function public.ride_rider(p_ride text, p_action text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  uid    text := (auth.uid())::text;
  r      jsonb;
  riders jsonb;
begin
  if uid is null then raise exception 'niet ingelogd' using errcode = '42501'; end if;
  if p_action not in ('ask', 'cancel') then raise exception 'onbekende actie'; end if;
  select data into r from public.docs where coll = 'rides' and id = p_ride for update;
  if r is null then raise exception 'rit niet gevonden'; end if;
  if r->>'driver' = uid then raise exception 'eigen rit' using errcode = '42501'; end if;
  if p_action = 'ask' and exists (
       select 1 from jsonb_array_elements(coalesce(r->'riders', '[]'::jsonb)) x where x->>'u' = uid) then
    return;
  end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into riders
    from jsonb_array_elements(coalesce(r->'riders', '[]'::jsonb)) x
    where x->>'u' <> uid;
  if p_action = 'ask' then
    riders := riders || jsonb_build_array(jsonb_build_object('u', uid, 's', 'ask'));
  end if;
  update public.docs set data = jsonb_set(data, '{riders}', riders), updated_at = now()
    where coll = 'rides' and id = p_ride;
end;
$$;

revoke all on function public.is_hh_member(text)            from public, anon;
revoke all on function public.doc_merge(text, text, jsonb)   from public, anon;
revoke all on function public.join_household(text)           from public, anon;
revoke all on function public.leave_household(text)          from public, anon;
revoke all on function public.ride_rider(text, text)         from public, anon;
grant execute on function public.is_hh_member(text)          to authenticated;
grant execute on function public.doc_merge(text, text, jsonb) to authenticated;
grant execute on function public.join_household(text)         to authenticated;
grant execute on function public.leave_household(text)        to authenticated;
grant execute on function public.ride_rider(text, text)       to authenticated;

-- Live bijwerken (Realtime)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docs') then
    alter publication supabase_realtime add table public.docs;
  end if;
end $$;

-- Berichten per rit (toegevoegd 21-10-2026)
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
