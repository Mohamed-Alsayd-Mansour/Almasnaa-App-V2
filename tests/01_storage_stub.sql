-- LOCAL TEST ONLY: minimal stand-in for Supabase Storage tables (schema "storage") used by 0006.
create schema if not exists storage;
create table storage.buckets (
  id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner_id text, metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select (string_to_array(name, '/'))[1:greatest(array_length(string_to_array(name,'/'),1)-1,0)] $$;
grant usage on schema storage to authenticated, anon, service_role;
grant select, insert, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;
