-- 0008: picking / changing the supervisor no longer creates a daily.
--
-- Root cause: change_supervisor() (0003) ended with "if sid is null then insert into daily_sessions ...",
-- so every supervisor pick (each rassas login, each supervisor change, each web reload that passes through
-- the pick screen) silently opened a new daily whenever none existed for that rassas+supervisor pair.
--
-- Now:
--   change_supervisor(p_supervisor, p_rassas)  -> links the supervisor and RESUMES an existing open daily of
--                                                 that pair if there is one. Returns its id, or NULL when
--                                                 there is none. It never inserts into daily_sessions.
--   create_session(p_supervisor, p_rassas)     -> the only way to open a new daily. Explicit, idempotent
--                                                 (an open daily of the pair is returned, not duplicated).
--
-- Safe to re-run: both functions are CREATE OR REPLACE with unchanged signatures/return types.
-- No table, column, index, policy or data is touched; existing dailies keep their owners.

create or replace function public.change_supervisor(p_supervisor uuid, p_rassas uuid default null)
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

  -- retrieve (never create) the open daily of this rassas+supervisor pair
  select id into sid from public.daily_sessions
   where rassas_id = v_rassas and supervisor_id = p_supervisor and status in ('active','paused') limit 1;

  -- the previously selected daily is paused (not closed, nothing lost)
  update public.daily_sessions set status = 'paused'
   where rassas_id = v_rassas and status = 'active' and id is distinct from sid;

  if sid is not null then
    update public.daily_sessions set status = 'active' where id = sid and status <> 'active';
  end if;
  return sid;   -- NULL = no open daily with this supervisor; the user creates one explicitly (create_session)
end $$;

-- Explicit creation. Rassas: for their current linked supervisor. Admin: must name the rassas.
-- Idempotent: if an open daily already exists for the pair it is selected and returned (no duplicate).
create or replace function public.create_session(p_supervisor uuid default null, p_rassas uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare r public.app_role := private.my_role(); v_rassas uuid; v_sup uuid; sid uuid;
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

  v_sup := private.current_supervisor_of(v_rassas);
  if v_sup is null then raise exception 'no supervisor selected'; end if;
  if p_supervisor is not null and p_supervisor <> v_sup then
    raise exception 'supervisor must equal the current linked supervisor' using errcode = '42501';
  end if;
  perform 1 from public.profiles
   where id = v_sup and role = 'supervisor' and status = 'active' and deleted_at is null;
  if not found then raise exception 'supervisor not found or disabled'; end if;

  select id into sid from public.daily_sessions
   where rassas_id = v_rassas and supervisor_id = v_sup and status in ('active','paused') limit 1;

  update public.daily_sessions set status = 'paused'
   where rassas_id = v_rassas and status = 'active' and id is distinct from sid;

  if sid is null then
    insert into public.daily_sessions(day_name, date, start_time, status, rassas_id, supervisor_id)
    values (private.arabic_day(now()), now(), now(), 'active', v_rassas, v_sup)
    returning id into sid;
  else
    update public.daily_sessions set status = 'active' where id = sid and status <> 'active';
  end if;
  return sid;
end $$;

revoke all on function public.create_session(uuid, uuid) from public, anon;
grant execute on function public.create_session(uuid, uuid) to authenticated;
