-- =====================================================================
-- Almasnaa v2.0 — 0003: RPC functions (login list, links, dailies, backup gate)
-- =====================================================================

-- ---------- login screen (callable BEFORE login) ----------
create function public.login_options(p_role public.app_role)
returns table (username text, display_name text, login_email text)
language sql stable security definer set search_path = public, auth as $$
  select p.username, p.display_name, u.email::text
  from public.profiles p join auth.users u on u.id = p.id
  where p.role = p_role and p.status = 'active' and p.deleted_at is null
  order by p.display_name
$$;
revoke all on function public.login_options(public.app_role) from public;
grant execute on function public.login_options(public.app_role) to anon, authenticated;

create function public.touch_login() returns void
language sql security definer set search_path = public as $$
  update public.profiles set last_login_at = now() where id = auth.uid() and status = 'active';
$$;
create function public.password_changed() returns void
language sql security definer set search_path = public as $$
  update public.profiles set must_change_password = false where id = auth.uid();
$$;

-- ---------- link + dailies ----------
create function private.arabic_day(p_ts timestamptz) returns text language sql immutable as $$
  select (array['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'])
         [extract(dow from p_ts at time zone 'Africa/Cairo')::int + 1]
$$;

-- Rassas picks / changes supervisor (admin may do it for a rassas).
-- Idempotent: repeating the same call never creates a duplicate daily.
create function public.change_supervisor(p_supervisor uuid, p_rassas uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare r public.app_role := private.my_role(); v_rassas uuid; cur uuid; sid uuid;
begin
  if r = 'rassas' then
    if p_rassas is not null and p_rassas <> auth.uid() then raise exception 'forbidden' using errcode = '42501'; end if;
    v_rassas := auth.uid();
  elsif r = 'admin' then
    if p_rassas is null then raise exception 'rassas id required'; end if;
    v_rassas := p_rassas;
  else
    raise exception 'forbidden' using errcode = '42501';
  end if;

  perform 1 from public.profiles
   where id = v_rassas and role = 'rassas' and status = 'active' and deleted_at is null for update;  -- serialises repeated taps
  if not found then raise exception 'rassas account not found or disabled'; end if;
  perform 1 from public.profiles
   where id = p_supervisor and role = 'supervisor' and status = 'active' and deleted_at is null;
  if not found then raise exception 'supervisor not found or disabled'; end if;

  cur := private.current_supervisor_of(v_rassas);
  if cur is distinct from p_supervisor then
    update public.rassas_supervisor_links set effective_to = now() where rassas_id = v_rassas and effective_to is null;
    insert into public.rassas_supervisor_links(rassas_id, supervisor_id, changed_by) values (v_rassas, p_supervisor, auth.uid());
  end if;

  select id into sid from public.daily_sessions
   where rassas_id = v_rassas and supervisor_id = p_supervisor and status in ('active','paused') limit 1;

  update public.daily_sessions set status = 'paused'
   where rassas_id = v_rassas and status = 'active' and id is distinct from sid;

  if sid is null then
    insert into public.daily_sessions(day_name, date, start_time, status, rassas_id, supervisor_id)
    values (private.arabic_day(now()), now(), now(), 'active', v_rassas, p_supervisor)
    returning id into sid;
  else
    update public.daily_sessions set status = 'active' where id = sid and status <> 'active';
  end if;
  return sid;
end $$;

-- Switch between the rassas's own open dailies (previous one becomes paused).
create function public.select_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.daily_sessions;
begin
  if private.my_role() <> 'rassas' then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into s from public.daily_sessions where id = p_session for update;
  if not found or s.rassas_id <> auth.uid() then raise exception 'daily not found'; end if;
  if s.status = 'closed' then raise exception 'daily is closed'; end if;
  update public.daily_sessions set status = 'paused' where rassas_id = auth.uid() and status = 'active' and id <> p_session;
  update public.daily_sessions set status = 'active' where id = p_session and status <> 'active';
end $$;

-- Explicit close only (rassas owner or admin).
create function public.close_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.daily_sessions; r public.app_role := private.my_role();
begin
  select * into s from public.daily_sessions where id = p_session for update;
  if not found then raise exception 'daily not found'; end if;
  if not (r = 'admin' or (r = 'rassas' and s.rassas_id = auth.uid())) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if s.status = 'closed' then return; end if;      -- idempotent
  update public.daily_sessions set status = 'closed', end_time = now() where id = p_session;
end $$;

-- ---------- backup password gate (separate from login & bulk-edit passwords) ----------
create table private.backup_attempts (
  user_id uuid not null, at timestamptz not null default now()
);

create function private.check_backup_password(p text) returns boolean
language plpgsql security definer set search_path = public, extensions, private as $$
declare h text; fails int;
begin
  select count(*) into fails from private.backup_attempts
   where user_id = auth.uid() and at > now() - interval '15 minutes';
  if fails >= 5 then return false; end if;
  select hash into h from private.secrets where key = 'backup_password';
  if h is null or p is null or crypt(p, h) <> h then
    insert into private.backup_attempts(user_id) values (auth.uid());
    return false;
  end if;
  return true;
end $$;
grant execute on function private.check_backup_password(text) to authenticated;

create function public.set_backup_password(p_new text) returns void
language plpgsql security definer set search_path = public, extensions, private as $$
begin
  if private.my_role() <> 'admin' then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_new is null or length(p_new) < 6 then raise exception 'password must be at least 6 characters'; end if;
  insert into private.secrets(key, hash) values ('backup_password', crypt(p_new, gen_salt('bf')))
  on conflict (key) do update set hash = excluded.hash, updated_at = now();
end $$;

create function private.safe_filename(p text) returns text language sql immutable as $$
  select regexp_replace(btrim(p), '[\\/:*?"<>|[:cntrl:]]', '_', 'g')
$$;

-- export what the caller may see (RLS applies: SECURITY INVOKER)
create function public.export_backup(p_password text) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare r public.app_role := private.my_role(); out jsonb; fname text; me text; sup text; sup_id uuid;
begin
  if r is null then raise exception 'forbidden' using errcode = '42501'; end if;
  if not private.check_backup_password(p_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_password');
  end if;
  me := private.name_of(auth.uid());
  if r = 'rassas' then
    sup_id := private.current_supervisor_of(auth.uid());
    sup := coalesce(private.name_of(sup_id), 'none');
    fname := 'almasnaa-data-' || private.safe_filename(me) || '-' || private.safe_filename(sup) || '.json';
  elsif r = 'supervisor' then
    fname := 'almasnaa-data-supervisor-' || private.safe_filename(me) || '.json';
  else
    fname := 'almasnaa-full-backup-' || to_char(now() at time zone 'Africa/Cairo', 'YYYY-MM-DD') || '.json';
  end if;
  out := jsonb_build_object(
    'ok', true, 'fileName', fname,
    'data', jsonb_build_object(
      'schemaVersion', 2, 'app', 'almasnaa', 'exportedAt', now(),
      'source', case when r = 'admin' then 'supabase-admin-full' else 'supabase-' || r::text end,
      'rassasId', case when r = 'rassas' then auth.uid() end,
      'supervisorId', case when r = 'rassas' then sup_id when r = 'supervisor' then auth.uid() end,
      'rooms',    coalesce((select jsonb_agg(to_jsonb(x)) from public.rooms x), '[]'),
      'people',   coalesce((select jsonb_agg(to_jsonb(x)) from public.people x), '[]'),
      'sessions', coalesce((select jsonb_agg(to_jsonb(x)) from public.daily_sessions x), '[]'),
      'entries',  coalesce((select jsonb_agg(to_jsonb(x)) from public.daily_entries x), '[]')));
  return out;
end $$;

-- import (admin only): validate -> summary (dry run) -> atomic apply. Existing ids are SKIPPED, never overwritten.
create function public.import_backup(p_password text, p_payload jsonb, p_apply boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  errs jsonb := '[]'; n jsonb; s_missing int; e_missing_s int; e_missing_r int; k text;
  c_rooms int; c_people int; c_sessions int; c_entries int;
begin
  if private.my_role() <> 'admin' then raise exception 'forbidden' using errcode = '42501'; end if;
  if not private.check_backup_password(p_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_password');
  end if;
  if coalesce(p_payload->>'app','') <> 'almasnaa' or coalesce(p_payload->>'schemaVersion','') <> '2' then
    return jsonb_build_object('ok', false, 'error', 'unsupported_file', 'detail', 'expected app=almasnaa, schemaVersion=2');
  end if;
  foreach k in array array['rooms','people','sessions','entries'] loop
    if jsonb_typeof(p_payload->k) is distinct from 'array' then
      errs := errs || to_jsonb('missing array: ' || k);
    end if;
  end loop;
  if jsonb_array_length(errs) > 0 then return jsonb_build_object('ok', false, 'error', 'bad_structure', 'detail', errs); end if;

  select count(*) into s_missing from jsonb_populate_recordset(null::public.daily_sessions, p_payload->'sessions') s
   where (s.rassas_id is not null and not exists (select 1 from public.profiles where id = s.rassas_id))
      or (s.supervisor_id is not null and not exists (select 1 from public.profiles where id = s.supervisor_id));
  select count(*) into e_missing_s from jsonb_populate_recordset(null::public.daily_entries, p_payload->'entries') e
   where not exists (select 1 from public.daily_sessions where id = e.daily_session_id)
     and not exists (select 1 from jsonb_populate_recordset(null::public.daily_sessions, p_payload->'sessions') s where s.id = e.daily_session_id);
  select count(*) into e_missing_r from jsonb_populate_recordset(null::public.daily_entries, p_payload->'entries') e
   where e.room_id is not null and not exists (select 1 from public.rooms where id = e.room_id)
     and not exists (select 1 from jsonb_populate_recordset(null::public.rooms, p_payload->'rooms') r where r.id = e.room_id);
  if s_missing > 0 then errs := errs || to_jsonb(s_missing || ' daily(ies) reference accounts that do not exist'); end if;
  if e_missing_s > 0 then errs := errs || to_jsonb(e_missing_s || ' entr(ies) reference a daily that does not exist'); end if;
  if e_missing_r > 0 then errs := errs || to_jsonb(e_missing_r || ' entr(ies) reference a room that does not exist'); end if;
  if jsonb_array_length(errs) > 0 then return jsonb_build_object('ok', false, 'error', 'broken_relations', 'detail', errs); end if;

  select count(*) into c_rooms    from jsonb_populate_recordset(null::public.rooms, p_payload->'rooms') x where not exists (select 1 from public.rooms t where t.id = x.id);
  select count(*) into c_people   from jsonb_populate_recordset(null::public.people, p_payload->'people') x where not exists (select 1 from public.people t where t.id = x.id);
  select count(*) into c_sessions from jsonb_populate_recordset(null::public.daily_sessions, p_payload->'sessions') x where not exists (select 1 from public.daily_sessions t where t.id = x.id);
  select count(*) into c_entries  from jsonb_populate_recordset(null::public.daily_entries, p_payload->'entries') x where not exists (select 1 from public.daily_entries t where t.id = x.id);
  n := jsonb_build_object('rooms', c_rooms, 'people', c_people, 'sessions', c_sessions, 'entries', c_entries);

  if not p_apply then
    return jsonb_build_object('ok', true, 'applied', false, 'wouldInsert', n, 'policy', 'existing ids are skipped');
  end if;

  perform set_config('app.bulk', 'on', true);
  perform set_config('app.audit_skip', 'on', true);
  insert into public.rooms          select * from jsonb_populate_recordset(null::public.rooms, p_payload->'rooms')          on conflict (id) do nothing;
  insert into public.people         select * from jsonb_populate_recordset(null::public.people, p_payload->'people')        on conflict (id) do nothing;
  insert into public.daily_sessions select * from jsonb_populate_recordset(null::public.daily_sessions, p_payload->'sessions') on conflict do nothing;
  insert into public.daily_entries  select * from jsonb_populate_recordset(null::public.daily_entries, p_payload->'entries')  on conflict do nothing;
  perform set_config('app.audit_skip', 'off', true);
  insert into public.audit_log(actor_id, actor_role, actor_name, op, entity, changes)
  values (auth.uid(), 'admin', private.name_of(auth.uid()), 'IMPORT', 'backup', n);
  return jsonb_build_object('ok', true, 'applied', true, 'inserted', n);
end $$;

-- bulk delete of operational data (admin only, separate password). Accounts, links, settings, audit are kept.
create function public.delete_all_data(p_password text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a int; b int; c int; d int;
begin
  if private.my_role() <> 'admin' then raise exception 'forbidden' using errcode = '42501'; end if;
  if not private.check_backup_password(p_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_password');
  end if;
  perform set_config('app.bulk', 'on', true);
  perform set_config('app.audit_skip', 'on', true);
  with x as (delete from public.daily_entries  returning 1) select count(*) into a from x;
  with x as (delete from public.daily_sessions returning 1) select count(*) into b from x;
  with x as (delete from public.rooms          returning 1) select count(*) into c from x;
  with x as (delete from public.people         returning 1) select count(*) into d from x;
  perform set_config('app.audit_skip', 'off', true);
  insert into public.audit_log(actor_id, actor_role, actor_name, op, entity, changes)
  values (auth.uid(), 'admin', private.name_of(auth.uid()), 'DELETE_ALL', 'operational_data',
          jsonb_build_object('entries', a, 'sessions', b, 'rooms', c, 'people', d));
  return jsonb_build_object('ok', true, 'deleted', jsonb_build_object('entries', a, 'sessions', b, 'rooms', c, 'people', d));
end $$;

-- expose RPCs to signed-in users only (role checks are inside each function)
revoke all on function public.touch_login(), public.password_changed(), public.change_supervisor(uuid, uuid),
  public.select_session(uuid), public.close_session(uuid), public.set_backup_password(text),
  public.export_backup(text), public.import_backup(text, jsonb, boolean), public.delete_all_data(text) from public, anon;
grant execute on function public.touch_login(), public.password_changed(), public.change_supervisor(uuid, uuid),
  public.select_session(uuid), public.close_session(uuid), public.set_backup_password(text),
  public.export_backup(text), public.import_backup(text, jsonb, boolean), public.delete_all_data(text) to authenticated;

grant execute on function private.name_of(uuid), private.safe_filename(text), private.arabic_day(timestamptz) to authenticated;
