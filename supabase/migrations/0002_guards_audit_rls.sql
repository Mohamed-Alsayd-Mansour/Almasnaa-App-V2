-- =====================================================================
-- Almasnaa v2.0 — 0002: helpers, integrity guards, audit/notifications, RLS
-- Guards run ONLY for authenticated end users (auth.uid() not null).
-- The service connection (migration, admin scripts) has auth.uid() = null.
-- =====================================================================

-- ---------- helpers (SECURITY DEFINER, no client write access) ----------
create function private.my_role() returns public.app_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles
  where id = auth.uid() and status = 'active' and deleted_at is null
$$;

create function private.session_status(p_id uuid) returns public.session_status
language sql stable security definer set search_path = public as $$
  select status from public.daily_sessions where id = p_id
$$;

create function private.sup_has_entry(p_session uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.daily_entries e
                 where e.daily_session_id = p_session and e.supervisor_id = auth.uid())
$$;

create function private.current_supervisor_of(p_rassas uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select supervisor_id from public.rassas_supervisor_links
  where rassas_id = p_rassas and effective_to is null
$$;

create function private.name_of(p_id uuid) returns text
language sql stable security definer set search_path = public as $$
  select display_name from public.profiles where id = p_id
$$;

-- ---------- guard: daily_sessions ----------
create function private.session_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.app_role;
begin
  if auth.uid() is null or current_setting('app.bulk', true) = 'on' then return new; end if;
  r := private.my_role();
  if r is null then raise exception 'forbidden' using errcode = '42501'; end if;

  if tg_op = 'INSERT' then
    if r = 'rassas' then
      new.rassas_id := auth.uid();
      if new.supervisor_id is distinct from private.current_supervisor_of(auth.uid()) then
        raise exception 'supervisor must equal the current linked supervisor' using errcode = '42501';
      end if;
    elsif r = 'admin' then
      if new.rassas_id is null or new.supervisor_id is null then
        raise exception 'rassas_id and supervisor_id are required';
      end if;
    else
      raise exception 'forbidden' using errcode = '42501';
    end if;
    new.rassas_name_snapshot     := coalesce(private.name_of(new.rassas_id), '');
    new.supervisor_name_snapshot := coalesce(private.name_of(new.supervisor_id), '');
    return new;
  end if;

  -- UPDATE
  if old.status = 'closed' then
    raise exception 'a closed daily is read-only' using errcode = '42501';
  end if;
  if new.date is distinct from old.date or new.start_time is distinct from old.start_time then
    raise exception 'date/start_time are immutable';
  end if;
  -- ownership is immutable; admin may only fill a NULL (legacy review) value
  if new.rassas_id is distinct from old.rassas_id and not (r = 'admin' and old.rassas_id is null) then
    raise exception 'rassas_id is immutable' using errcode = '42501';
  end if;
  if new.supervisor_id is distinct from old.supervisor_id and not (r = 'admin' and old.supervisor_id is null) then
    raise exception 'supervisor_id is immutable' using errcode = '42501';
  end if;
  if new.status = 'closed' and new.end_time is null then new.end_time := now(); end if;
  return new;
end $$;
create trigger sessions_guard_i before insert on public.daily_sessions for each row execute function private.session_guard();
create trigger sessions_guard_u before update on public.daily_sessions for each row execute function private.session_guard();

-- ---------- guard: daily_entries ----------
create function private.entry_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r public.app_role; s public.daily_sessions; st public.session_status;
  allowed text[] := array['specifications_text','current_deficiencies','current_missing_count',
                          'last_deficiency_update_at','problem','updated_at'];
  bad text;
begin
  if auth.uid() is null or current_setting('app.bulk', true) = 'on' then return new; end if;
  r := private.my_role();
  if r is null then raise exception 'forbidden' using errcode = '42501'; end if;

  if tg_op = 'INSERT' then
    select * into s from public.daily_sessions where id = new.daily_session_id;
    if not found then raise exception 'daily not found'; end if;
    if r = 'rassas' then
      if s.rassas_id is distinct from auth.uid() then raise exception 'forbidden' using errcode = '42501'; end if;
    elsif r <> 'admin' then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    if s.status = 'closed' then raise exception 'daily is closed'; end if;
    if s.status = 'paused' then raise exception 'daily is paused; select it first'; end if;
    new.rassas_id     := s.rassas_id;
    new.supervisor_id := s.supervisor_id;
    new.installer     := s.rassas_name_snapshot;
    new.supervisor    := s.supervisor_name_snapshot;
    return new;
  end if;

  -- UPDATE
  if new.daily_session_id is distinct from old.daily_session_id or new.created_at is distinct from old.created_at then
    raise exception 'daily_session_id/created_at are immutable' using errcode = '42501';
  end if;
  if new.rassas_id is distinct from old.rassas_id and not (r = 'admin' and old.rassas_id is null) then
    raise exception 'rassas_id is immutable' using errcode = '42501';
  end if;
  if new.supervisor_id is distinct from old.supervisor_id and not (r = 'admin' and old.supervisor_id is null) then
    raise exception 'supervisor_id is immutable' using errcode = '42501';
  end if;

  if r = 'rassas' then
    st := private.session_status(old.daily_session_id);
    if st = 'closed' then
      -- "السجل": rassas may live-edit only 4 fields (+ derived current missing count)
      if old.is_order then allowed := allowed || 'room_name_snapshot'; end if;
      select n.key into bad
      from jsonb_each(to_jsonb(new)) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
      where n.value is distinct from o.value and n.key <> all (allowed)
      limit 1;
      if bad is not null then
        raise exception 'rassas may not edit field % of a closed record', bad using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger entries_guard_i before insert on public.daily_entries for each row execute function private.entry_guard();
create trigger entries_guard_u before update on public.daily_entries for each row execute function private.entry_guard();

-- ---------- audit + notification fan-out ----------
create function private.audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j_new jsonb; j_old jsonb; base jsonb; ch jsonb; aid bigint;
  a_role public.app_role; a_name text; sid uuid; ras uuid; sup uuid;
begin
  if current_setting('app.audit_skip', true) = 'on' then return coalesce(new, old); end if;
  j_new := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  j_old := case when tg_op <> 'INSERT' then to_jsonb(old) end;

  if tg_op = 'UPDATE' then
    select jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value)) into ch
    from jsonb_each(j_new) n join jsonb_each(j_old) o on o.key = n.key
    where n.value is distinct from o.value and n.key not in ('updated_at','last_login_at');
    if ch is null then return new; end if;
  elsif tg_op = 'INSERT' then ch := j_new;
  else ch := j_old; end if;

  base := coalesce(j_new, j_old);
  if tg_table_name = 'daily_entries' then sid := (base->>'daily_session_id')::uuid;
  elsif tg_table_name = 'daily_sessions' then sid := (base->>'id')::uuid; end if;
  ras := (base->>'rassas_id')::uuid;
  sup := (base->>'supervisor_id')::uuid;

  select p.role, p.display_name into a_role, a_name from public.profiles p where p.id = auth.uid();

  insert into public.audit_log(actor_id, actor_role, actor_name, op, entity, entity_id, changes, session_id, rassas_id, supervisor_id)
  values (auth.uid(), a_role, coalesce(a_name, 'system'), tg_op, tg_table_name, base->>'id', ch, sid, ras, sup)
  returning id into aid;

  -- recipients: every admin + the rassas/supervisor the record belongs to (by UUID, not by current link)
  insert into public.notifications(recipient_id, audit_id)
  select p.id, aid from public.profiles p
  where p.status = 'active' and p.deleted_at is null
    and p.id is distinct from auth.uid()
    and (p.role = 'admin' or p.id in (ras, sup))
  on conflict do nothing;

  return coalesce(new, old);
end $$;

create trigger audit_entries  after insert or update or delete on public.daily_entries  for each row execute function private.audit();
create trigger audit_sessions after insert or update or delete on public.daily_sessions for each row execute function private.audit();
create trigger audit_rooms    after insert or update or delete on public.rooms          for each row execute function private.audit();
create trigger audit_people   after insert or update or delete on public.people         for each row execute function private.audit();
create trigger audit_links    after insert or update or delete on public.rassas_supervisor_links for each row execute function private.audit();
create trigger audit_profiles after insert or update or delete on public.profiles       for each row execute function private.audit();
create trigger audit_settings after insert or update or delete on public.app_settings   for each row execute function private.audit();

-- ---------- grants (RLS does the row filtering) ----------
revoke all on all tables in schema public from anon, authenticated;
revoke all on schema private from anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.my_role(), private.session_status(uuid), private.sup_has_entry(uuid),
                          private.current_supervisor_of(uuid) to authenticated;

grant select on public.profiles, public.rassas_supervisor_links, public.audit_log, public.migration_review to authenticated;
grant select, insert, update, delete on public.people, public.rooms, public.daily_entries to authenticated;
grant select, insert, update, delete on public.daily_sessions to authenticated;
grant select, insert, update on public.app_settings to authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- directory of ACTIVE users (names only) for dropdowns, @mentions, chat
create view public.directory as
  select id, username, display_name, role from public.profiles
  where status = 'active' and deleted_at is null;
grant select on public.directory to authenticated;

-- ---------- RLS ----------
alter table public.profiles                enable row level security;
alter table public.people                  enable row level security;
alter table public.rooms                   enable row level security;
alter table public.rassas_supervisor_links enable row level security;
alter table public.daily_sessions          enable row level security;
alter table public.daily_entries           enable row level security;
alter table public.app_settings            enable row level security;
alter table public.audit_log               enable row level security;
alter table public.notifications           enable row level security;
alter table public.migration_review        enable row level security;
alter table private.secrets                enable row level security;   -- no policies => unreachable

-- profiles: own row, admin sees all. Writes only via admin Edge Function / service role.
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or private.my_role() = 'admin');

-- people (operational name lists): everyone reads; admin + supervisor manage
create policy people_select on public.people for select to authenticated using (private.my_role() is not null);
create policy people_write  on public.people for all to authenticated
  using (private.my_role() in ('admin','supervisor')) with check (private.my_role() in ('admin','supervisor'));

-- rooms catalogue: everyone reads; admin + rassas manage; supervisor read-only
create policy rooms_select on public.rooms for select to authenticated using (private.my_role() is not null);
create policy rooms_write  on public.rooms for all to authenticated
  using (private.my_role() in ('admin','rassas')) with check (private.my_role() in ('admin','rassas'));

-- links: read only (changes go through change_supervisor())
create policy links_select on public.rassas_supervisor_links for select to authenticated
  using (private.my_role() = 'admin' or rassas_id = auth.uid() or supervisor_id = auth.uid());

-- dailies
create policy sessions_select on public.daily_sessions for select to authenticated
  using (private.my_role() = 'admin'
      or (private.my_role() = 'rassas' and rassas_id = auth.uid())
      or (private.my_role() = 'supervisor' and (supervisor_id = auth.uid() or private.sup_has_entry(id))));
create policy sessions_insert on public.daily_sessions for insert to authenticated
  with check (private.my_role() in ('admin','rassas'));
create policy sessions_update on public.daily_sessions for update to authenticated
  using (private.my_role() = 'admin' or (private.my_role() = 'rassas' and rassas_id = auth.uid()))
  with check (private.my_role() = 'admin' or (private.my_role() = 'rassas' and rassas_id = auth.uid()));
create policy sessions_delete on public.daily_sessions for delete to authenticated
  using (private.my_role() = 'admin');

-- entries: owner by UUID only (a supervisor never sees another supervisor's entry)
create policy entries_select on public.daily_entries for select to authenticated
  using (private.my_role() = 'admin'
      or (private.my_role() = 'rassas'     and rassas_id     = auth.uid())
      or (private.my_role() = 'supervisor' and supervisor_id = auth.uid()));
create policy entries_insert on public.daily_entries for insert to authenticated
  with check (private.my_role() in ('admin','rassas'));
create policy entries_update on public.daily_entries for update to authenticated
  using (private.my_role() = 'admin'
      or (private.my_role() = 'rassas'     and rassas_id     = auth.uid())
      or (private.my_role() = 'supervisor' and supervisor_id = auth.uid()))
  with check (private.my_role() = 'admin'
      or (private.my_role() = 'rassas'     and rassas_id     = auth.uid())
      or (private.my_role() = 'supervisor' and supervisor_id = auth.uid()));
create policy entries_delete on public.daily_entries for delete to authenticated
  using (private.my_role() = 'admin'
      or (private.my_role() = 'rassas' and rassas_id = auth.uid() and private.session_status(daily_session_id) <> 'closed')
      or (private.my_role() = 'supervisor' and supervisor_id = auth.uid()));

-- settings (non-secret, shared): all read, admin writes
create policy settings_select on public.app_settings for select to authenticated using (private.my_role() is not null);
create policy settings_write  on public.app_settings for all to authenticated
  using (private.my_role() = 'admin') with check (private.my_role() = 'admin');

-- audit: admin all; others only rows that belong to them by UUID
create policy audit_select on public.audit_log for select to authenticated
  using (private.my_role() = 'admin' or rassas_id = auth.uid() or supervisor_id = auth.uid());

-- notifications: own only; may only set read_at (column grant)
create policy notif_select on public.notifications for select to authenticated using (recipient_id = auth.uid());
create policy notif_update on public.notifications for update to authenticated
  using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

create policy review_select on public.migration_review for select to authenticated using (private.my_role() = 'admin');

-- ---------- realtime ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.daily_entries, public.daily_sessions,
      public.rooms, public.people, public.notifications, public.rassas_supervisor_links, public.app_settings;
  end if;
end $$;
