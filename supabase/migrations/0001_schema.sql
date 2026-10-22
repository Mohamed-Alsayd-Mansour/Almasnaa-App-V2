-- =====================================================================
-- Almasnaa v2.0 — 0001: core schema (Supabase / PostgreSQL 15+)
-- Order of execution: 0001 -> 0002 -> 0003 -> 0004
-- Roles: admin | rassas | supervisor.  All tables use UUID primary keys.
-- Names are SNAPSHOTS in historical rows; ownership is by UUID.
-- =====================================================================
create extension if not exists pgcrypto;
create schema if not exists private;

-- ---------- enums ----------
create type public.app_role       as enum ('admin','rassas','supervisor');
create type public.account_status as enum ('active','disabled');
create type public.person_role    as enum ('service','carpenter','installer','supervisor','repairer','wrapLocation');
create type public.session_status as enum ('active','paused','closed');   -- active = currently selected by its rassas

-- ---------- accounts ----------
create table public.profiles (
  id                   uuid primary key references auth.users(id) on delete restrict,
  username             text not null check (length(btrim(username)) > 0),
  display_name         text not null,
  role                 public.app_role not null,
  status               public.account_status not null default 'active',
  must_change_password boolean not null default false,
  created_at           timestamptz not null default now(),
  last_login_at        timestamptz,
  deleted_at           timestamptz            -- logical delete; history is never broken
);
create unique index profiles_username_uq on public.profiles (lower(btrim(username))) where deleted_at is null;

-- ---------- operational name lists (v1 "people") ----------
create table public.people (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  role       public.person_role not null,
  created_at timestamptz not null default now()
);

-- ---------- rooms catalogue ----------
create table public.rooms (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  piece_count           int  not null default 0,
  glass_piece_count     int  not null default 0,
  partition_piece_count int  not null default 0,
  partition_count       int  not null default 0,   -- display only, never part of totals
  marble_piece_count    int  not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- ---------- rassas <-> supervisor link history ----------
create table public.rassas_supervisor_links (
  id             uuid primary key default gen_random_uuid(),
  rassas_id      uuid not null references public.profiles(id),
  supervisor_id  uuid not null references public.profiles(id),
  effective_from timestamptz not null default now(),
  effective_to   timestamptz,
  changed_by     uuid references public.profiles(id)
);
create unique index links_one_current_per_rassas on public.rassas_supervisor_links (rassas_id) where effective_to is null;
create index links_supervisor_idx on public.rassas_supervisor_links (supervisor_id) where effective_to is null;

-- ---------- dailies (sessions) ----------
create table public.daily_sessions (
  id                     uuid primary key default gen_random_uuid(),
  day_name               text not null,
  date                   timestamptz not null,
  start_time             timestamptz not null,
  end_time               timestamptz,
  status                 public.session_status not null default 'active',
  rassas_id              uuid references public.profiles(id),     -- NULL only for unresolved legacy rows
  supervisor_id          uuid references public.profiles(id),     -- supervisor at CREATION time; never rewritten
  rassas_name_snapshot   text not null default '',
  supervisor_name_snapshot text not null default '',
  client_op_id           uuid unique,                              -- idempotency key from the client
  legacy_id              text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
create unique index sessions_one_selected_per_rassas on public.daily_sessions (rassas_id) where status = 'active';
create unique index sessions_one_open_per_pair      on public.daily_sessions (rassas_id, supervisor_id) where status in ('active','paused');
create index sessions_supervisor_idx on public.daily_sessions (supervisor_id);

-- ---------- production entries ----------
create table public.daily_entries (
  id                       uuid primary key default gen_random_uuid(),
  daily_session_id         uuid not null references public.daily_sessions(id) on delete restrict,
  room_id                  uuid references public.rooms(id) on delete set null,
  room_name_snapshot       text not null default '',
  piece_count_snapshot     int  not null default 0,
  is_external              boolean not null default false,
  is_order                 boolean not null default false,
  merchant_name            text not null default '',
  customer_name            text not null default '',
  numbering                text not null default '',
  carpenter                text not null default '',
  service                  text not null default '',
  installer                text not null default '',   -- snapshot of rassas name (v1 column kept)
  supervisor               text not null default '',   -- snapshot of supervisor name (v1 column kept)
  repairer                 text not null default '',
  wrap_location            text not null default '',
  has_specifications       boolean not null default false,
  specifications_text      text not null default '',
  special_piece_count      int  not null default 0,
  problem                  text not null default '',
  is_partial               boolean not null default false,
  part_name                text not null default '',
  partial_piece_count      int  not null default 0,
  original_deficiencies    text not null default '',
  current_deficiencies     text not null default '',
  original_missing_count   int  not null default 0,
  current_missing_count    int  not null default 0,
  last_deficiency_update_at timestamptz,
  rassas_id                uuid references public.profiles(id),
  supervisor_id            uuid references public.profiles(id),
  needs_review             boolean not null default false,
  client_op_id             uuid unique,
  legacy_room_id           text,                        -- v1 room id even if the room was deleted later
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index entries_session_idx    on public.daily_entries (daily_session_id);
create index entries_rassas_idx     on public.daily_entries (rassas_id);
create index entries_supervisor_idx on public.daily_entries (supervisor_id);

-- ---------- shared settings (never secrets) ----------
create table public.app_settings (
  key        text primary key,
  value      jsonb not null,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

-- ---------- secrets (not reachable by any client role) ----------
create table private.secrets (
  key        text primary key,
  hash       text not null,          -- crypt() hash only
  updated_at timestamptz not null default now()
);

-- ---------- audit + notifications ----------
create table public.audit_log (
  id            bigint generated always as identity primary key,
  at            timestamptz not null default now(),   -- server time
  actor_id      uuid,
  actor_role    public.app_role,
  actor_name    text not null default 'system',
  op            text not null,                         -- INSERT/UPDATE/DELETE/IMPORT/DELETE_ALL
  entity        text not null,
  entity_id     text,
  changes       jsonb,                                 -- {col:{old,new}} for UPDATE, full row for INSERT/DELETE
  session_id    uuid,
  rassas_id     uuid,
  supervisor_id uuid
);
create index audit_rassas_idx on public.audit_log (rassas_id);
create index audit_supervisor_idx on public.audit_log (supervisor_id);
create index audit_session_idx on public.audit_log (session_id);

create table public.notifications (
  id           bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles(id),
  audit_id     bigint not null references public.audit_log(id) on delete cascade,
  created_at   timestamptz not null default now(),
  read_at      timestamptz,
  unique (recipient_id, audit_id)                      -- retry-safe: no duplicates
);
create index notif_recipient_idx on public.notifications (recipient_id, read_at);

-- ---------- migration review list ----------
create table public.migration_review (
  id         bigint generated always as identity primary key,
  entity     text not null,
  entity_id  text not null,
  reason     text not null,
  created_at timestamptz not null default now(),
  unique (entity, entity_id, reason)
);

-- ---------- generic updated_at ----------
create function private.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger rooms_touch    before update on public.rooms          for each row execute function private.touch_updated_at();
create trigger sessions_touch before update on public.daily_sessions for each row execute function private.touch_updated_at();
create trigger entries_touch  before update on public.daily_entries  for each row execute function private.touch_updated_at();
