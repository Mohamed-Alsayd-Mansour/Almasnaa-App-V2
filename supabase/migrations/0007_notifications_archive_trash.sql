-- =====================================================================
-- Almasnaa v2.0 — 0007: notification archive + trash (soft delete) + permanent delete
--   inbox   : archived_at is null and deleted_at is null
--   archive : archived_at is not null and deleted_at is null   (reversible)
--   trash   : deleted_at is not null                           (restorable; permanent delete only from here)
-- Everything stays per-recipient (RLS) and the sync/realtime of public.notifications is unchanged.
-- =====================================================================
alter table public.notifications
  add column archived_at timestamptz,
  add column deleted_at  timestamptz;

create index notif_state_idx on public.notifications (recipient_id, deleted_at, archived_at);

-- a recipient may change ONLY these three columns of his own rows (policy notif_update already pins recipient_id)
revoke update on public.notifications from authenticated;
grant update (read_at, archived_at, deleted_at) on public.notifications to authenticated;

-- permanent deletion: own rows, and ONLY after they were moved to the trash
grant delete on public.notifications to authenticated;
create policy notif_delete on public.notifications for delete to authenticated
  using (recipient_id = auth.uid() and deleted_at is not null);
