-- 0009: rassas / supervisor NAMES are identity data, not free text.
--
-- Gaps found (reproduced against 0001..0008 with direct PostgREST-style updates):
--   * a rassas or a supervisor could overwrite daily_entries.installer / .supervisor (the two name columns);
--   * a rassas could overwrite daily_sessions.rassas_name_snapshot / supervisor_name_snapshot;
--   * anyone allowed on `people` (admin, supervisor) could add rows with role installer/supervisor, i.e. a
--     second, hand-typed list of rassas/supervisor names beside the user accounts.
--
-- Fix (server-side; the UI is only a convenience):
--   * names on entries and on the daily's snapshot may be changed by an ADMIN only;
--   * ownership stays by UUID (rassas_id / supervisor_id, already immutable) and names are still snapshotted
--     at creation from profiles, so renaming an account never rewrites history (no trigger touches old rows);
--   * `people` no longer accepts installer/supervisor names (existing legacy rows are left untouched and can
--     still be deleted; nothing is removed here).
-- Safe to re-run: CREATE OR REPLACE / DROP TRIGGER IF EXISTS only. No data is changed.

-- 1) entries ----------------------------------------------------------------------------------------------
create or replace function private.entry_guard() returns trigger
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
    if new.is_external then
      -- v1 behaviour: external rooms show no rassas/supervisor NAME; ownership is still by id
      new.installer := ''; new.supervisor := '';
    else
      new.installer  := s.rassas_name_snapshot;
      new.supervisor := s.supervisor_name_snapshot;
    end if;
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
  -- NEW (0009): the rassas / supervisor names on a record are editable by the admin only
  if r <> 'admin' and (new.installer is distinct from old.installer or new.supervisor is distinct from old.supervisor) then
    raise exception 'rassas/supervisor names can only be edited by an admin' using errcode = '42501';
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

-- 2) daily sessions ---------------------------------------------------------------------------------------
create or replace function private.session_guard() returns trigger
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
  -- NEW (0009): the name snapshots are editable by the admin only
  if r <> 'admin' and (new.rassas_name_snapshot is distinct from old.rassas_name_snapshot
                    or new.supervisor_name_snapshot is distinct from old.supervisor_name_snapshot) then
    raise exception 'rassas/supervisor names can only be edited by an admin' using errcode = '42501';
  end if;
  if new.status = 'closed' and new.end_time is null then new.end_time := now(); end if;
  return new;
end $$;

-- 3) people: no hand-typed rassas/supervisor names beside the accounts ------------------------------------
create or replace function private.people_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or current_setting('app.bulk', true) = 'on' then return new; end if;   -- backup restore / SQL editor
  if new.role in ('installer', 'supervisor')
     and (tg_op = 'INSERT' or new.role is distinct from old.role or new.name is distinct from old.name) then
    raise exception 'rassas/supervisor names come from user accounts, not from the names list' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists people_guard_iu on public.people;
create trigger people_guard_iu before insert or update on public.people
  for each row execute function private.people_guard();
