-- =====================================================================
-- Almasnaa v2.0 — 0005 (Phase 3): external rooms keep blank name snapshots (v1 behaviour)
-- Entry ownership (rassas_id / supervisor_id) is still forced from the daily for ALL entries.
-- =====================================================================
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

