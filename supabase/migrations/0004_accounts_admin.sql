-- =====================================================================
-- Almasnaa v2.0 — 0004: account administration rules + owner assignment
-- Admin manages profiles through the 'admin-users' Edge Function, which runs the
-- profile DML with the ADMIN'S OWN JWT (so audit_log records the real executor).
-- These rules are enforced here, so they also hold for direct API calls.
-- =====================================================================
grant insert, update, delete on public.profiles to authenticated;

create policy profiles_admin_insert on public.profiles for insert to authenticated with check (private.my_role() = 'admin');
create policy profiles_admin_update on public.profiles for update to authenticated
  using (private.my_role() = 'admin') with check (private.my_role() = 'admin');
create policy profiles_admin_delete on public.profiles for delete to authenticated using (private.my_role() = 'admin');

create function private.has_history(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.daily_sessions where rassas_id = p_id or supervisor_id = p_id)
      or exists (select 1 from public.daily_entries  where rassas_id = p_id or supervisor_id = p_id)
      or exists (select 1 from public.rassas_supervisor_links where rassas_id = p_id or supervisor_id = p_id)
      or exists (select 1 from public.audit_log where actor_id = p_id)
$$;

create function private.other_active_admins(p_id uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.profiles
  where role = 'admin' and status = 'active' and deleted_at is null and id <> p_id
$$;

create function private.profile_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or current_setting('app.bulk', true) = 'on' then return coalesce(new, old); end if;

  if tg_op = 'INSERT' then
    return new;
  elsif tg_op = 'DELETE' then
    if old.id = auth.uid() then raise exception 'you cannot delete your own account' using errcode = '42501'; end if;
    if private.has_history(old.id) then
      raise exception 'account has history; disable / logically delete it instead' using errcode = '23503';
    end if;
    if old.role = 'admin' and old.status = 'active' and private.other_active_admins(old.id) = 0 then
      raise exception 'cannot remove the last active admin' using errcode = '42501';
    end if;
    return old;
  end if;

  -- UPDATE
  if new.id is distinct from old.id then raise exception 'id is immutable'; end if;
  if new.role is distinct from old.role then
    if old.id = auth.uid() then raise exception 'you cannot change your own role' using errcode = '42501'; end if;
    if private.has_history(old.id) then raise exception 'role cannot change once the account has history' using errcode = '23503'; end if;
  end if;
  if old.status = 'active' and old.deleted_at is null and (new.status = 'disabled' or new.deleted_at is not null) then
    if old.id = auth.uid() then raise exception 'you cannot disable your own account' using errcode = '42501'; end if;
    if old.role = 'admin' and private.other_active_admins(old.id) = 0 then
      raise exception 'cannot disable the last active admin' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger profiles_guard before insert or update or delete on public.profiles for each row execute function private.profile_guard();

-- Admin assigns owners to historical entries that v1 never tied to a rassas/supervisor.
create function public.assign_entry_owner(p_entry_ids uuid[], p_rassas uuid, p_supervisor uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if private.my_role() <> 'admin' then raise exception 'forbidden' using errcode = '42501'; end if;
  perform 1 from public.profiles where id = p_rassas and role = 'rassas' and deleted_at is null;
  if not found then raise exception 'rassas not found'; end if;
  perform 1 from public.profiles where id = p_supervisor and role = 'supervisor' and deleted_at is null;
  if not found then raise exception 'supervisor not found'; end if;

  update public.daily_entries
     set rassas_id = p_rassas, supervisor_id = p_supervisor,
         installer = private.name_of(p_rassas), supervisor = private.name_of(p_supervisor),
         needs_review = false
   where id = any(p_entry_ids) and rassas_id is null and supervisor_id is null;
  get diagnostics n = row_count;

  delete from public.migration_review
   where entity = 'daily_entries' and entity_id = any (select x::text from unnest(p_entry_ids) x)
     and reason like 'no rassas/supervisor%';
  return n;
end $$;
revoke all on function public.assign_entry_owner(uuid[], uuid, uuid) from public, anon;
grant execute on function public.assign_entry_owner(uuid[], uuid, uuid) to authenticated;
