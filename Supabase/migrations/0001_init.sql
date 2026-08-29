-- 78th: social schema.
--
-- Two rules shape this file:
--   1. Visibility is enforced here, in row level security, not in the client. A
--      modified app must not be able to see more than the real one.
--   2. Nothing about a student's schedule exists on this server. There is no
--      table for it, because it never leaves the phone.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

-- A short, unambiguous code. No vowels and no 0/O/1/I, so a code read aloud in
-- a hallway does not turn into someone else's code.
create or replace function public.generate_friend_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := '23456789BCDFGHJKLMNPQRSTVWXZ';
  candidate text;
begin
  loop
    candidate := '78TH-' || (
      select string_agg(substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1), '')
      from generate_series(1, 4)
    );
    exit when not exists (select 1 from public.profiles where friend_code = candidate);
  end loop;
  return candidate;
end;
$$;

create table if not exists public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  display_name   text not null check (char_length(trim(display_name)) between 1 and 40),
  grade          smallint check (grade between 6 and 12),
  avatar_emoji   text not null default '🙂' check (char_length(avatar_emoji) <= 8),
  friend_code    text not null unique default public.generate_friend_code(),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Friendships
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'friendship_status') then
    create type public.friendship_status as enum ('pending', 'accepted', 'blocked');
  end if;
end
$$;

create table if not exists public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references auth.users (id) on delete cascade,
  addressee_id  uuid not null references auth.users (id) on delete cascade,
  status        public.friendship_status not null default 'pending',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint friendships_not_self check (requester_id <> addressee_id),
  constraint friendships_direction_unique unique (requester_id, addressee_id)
);

-- One live relationship per pair, whichever direction it was created in. Blocks
-- are directional and excluded, so A can block B while B has also blocked A.
create unique index if not exists friendships_pair_unique
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id))
  where status <> 'blocked';

create index if not exists friendships_addressee_idx on public.friendships (addressee_id, status);
create index if not exists friendships_requester_idx on public.friendships (requester_id, status);

-- ---------------------------------------------------------------------------
-- Pings
-- ---------------------------------------------------------------------------

-- The location and note lists are constrained here as well as in the app. A
-- closed vocabulary is the feature, so it is enforced where it cannot be
-- bypassed. Changing the building's spots means a migration, on purpose.
create table if not exists public.pings (
  id            uuid primary key default gen_random_uuid(),
  -- One live ping per student. A new ping replaces the old one rather than
  -- appending, so there is never a trail to read.
  user_id       uuid not null unique references auth.users (id) on delete cascade,
  location_key  text not null check (location_key in (
                  'lobby', 'lounge3', 'lounge4', 'lounge6', 'library',
                  'cafeteria', 'gym', 'beitMidrash', 'outside')),
  note_key      text check (note_key in (
                  'freeNow', 'studying', 'eating', 'comeThrough', 'leavingSoon')),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  -- 45 minutes is the ceiling from the spec. The app sends the end of the
  -- current period when that is sooner; the server only enforces the maximum,
  -- because it does not know anyone's schedule.
  constraint pings_lifetime check (
    expires_at > created_at and expires_at <= created_at + interval '45 minutes'
  )
);

create index if not exists pings_expiry_idx on public.pings (expires_at);

-- ---------------------------------------------------------------------------
-- Device tokens
-- ---------------------------------------------------------------------------

create table if not exists public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  apns_token  text not null unique,
  updated_at  timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Relationship helpers
-- ---------------------------------------------------------------------------

-- security definer so that policies on friendships can call these without
-- recursing through those same policies.

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$$;

create or replace function public.has_pending_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships
    where status = 'pending'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$$;

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships
    where status = 'blocked'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles      enable row level security;
alter table public.friendships   enable row level security;
alter table public.pings         enable row level security;
alter table public.device_tokens enable row level security;

-- Profiles: yourself, your accepted friends, and anyone in a pending request
-- with you. Nothing wider: there is no directory to browse.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or public.are_friends((select auth.uid()), id)
    or public.has_pending_between((select auth.uid()), id)
  );

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles
  for delete to authenticated
  using (id = (select auth.uid()));

-- Friendships: only rows you are part of.
drop policy if exists friendships_select on public.friendships;
create policy friendships_select on public.friendships
  for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

drop policy if exists friendships_insert on public.friendships;
create policy friendships_insert on public.friendships
  for insert to authenticated
  with check (requester_id = (select auth.uid()));

-- Only the person a request was sent to can accept it.
drop policy if exists friendships_update on public.friendships;
create policy friendships_update on public.friendships
  for update to authenticated
  using (addressee_id = (select auth.uid()))
  with check (addressee_id = (select auth.uid()));

drop policy if exists friendships_delete on public.friendships;
create policy friendships_delete on public.friendships
  for delete to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

-- Pings: your own, plus live pings from accepted friends. This policy is the
-- whole privacy model of the feature.
drop policy if exists pings_select on public.pings;
create policy pings_select on public.pings
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (public.are_friends((select auth.uid()), user_id) and expires_at > now())
  );

drop policy if exists pings_insert on public.pings;
create policy pings_insert on public.pings
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists pings_update on public.pings;
create policy pings_update on public.pings
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists pings_delete on public.pings;
create policy pings_delete on public.pings
  for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists device_tokens_all on public.device_tokens;
create policy device_tokens_all on public.device_tokens
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- The one read the app makes for the Pings screen
-- ---------------------------------------------------------------------------

-- security_invoker means the caller's policies apply to the underlying tables,
-- so this view cannot widen what anyone can see.
create or replace view public.friend_pings
with (security_invoker = true)
as
  select
    p.id,
    p.user_id,
    p.location_key,
    p.note_key,
    p.created_at,
    p.expires_at,
    pr.display_name,
    pr.grade,
    pr.avatar_emoji
  from public.pings p
  join public.profiles pr on pr.id = p.user_id
  where p.expires_at > now()
    and p.user_id <> (select auth.uid());

grant select on public.friend_pings to authenticated;

-- ---------------------------------------------------------------------------
-- Operations the client cannot express safely as a query
-- ---------------------------------------------------------------------------

-- Adding by code has to be a function: a plain select on profiles by code would
-- let anyone enumerate the school by guessing codes.
create or replace function public.request_friend_by_code(code text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  me      uuid := auth.uid();
  target  public.profiles;
begin
  if me is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;

  select * into target from public.profiles where friend_code = upper(trim(code));
  if not found then
    raise exception 'unknown_code' using errcode = 'P0002';
  end if;

  if target.id = me then
    raise exception 'self_request' using errcode = 'P0001';
  end if;

  if public.is_blocked_between(me, target.id) then
    -- Deliberately indistinguishable from an unknown code: a blocked student
    -- should not learn that they were blocked.
    raise exception 'unknown_code' using errcode = 'P0002';
  end if;

  if public.are_friends(me, target.id) then
    raise exception 'already_friends' using errcode = 'P0001';
  end if;

  -- If they already asked you, saying yes is the same as asking back.
  if exists (
    select 1 from public.friendships
    where status = 'pending' and requester_id = target.id and addressee_id = me
  ) then
    update public.friendships
       set status = 'accepted', updated_at = now()
     where requester_id = target.id and addressee_id = me;
    return target;
  end if;

  insert into public.friendships (requester_id, addressee_id, status)
  values (me, target.id, 'pending')
  on conflict do nothing;

  return target;
end;
$$;

create or replace function public.accept_friend_request(friendship_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.friendships
     set status = 'accepted', updated_at = now()
   where id = friendship_id
     and addressee_id = auth.uid()
     and status = 'pending';
end;
$$;

create or replace function public.remove_friend(other_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  delete from public.friendships
   where status <> 'blocked'
     and ((requester_id = me and addressee_id = other_id)
       or (requester_id = other_id and addressee_id = me));
end;
$$;

create or replace function public.block_user(other_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null or me = other_id then
    return;
  end if;

  delete from public.friendships
   where status <> 'blocked'
     and ((requester_id = me and addressee_id = other_id)
       or (requester_id = other_id and addressee_id = me));

  insert into public.friendships (requester_id, addressee_id, status)
  values (me, other_id, 'blocked')
  on conflict (requester_id, addressee_id)
  do update set status = 'blocked', updated_at = now();
end;
$$;

create or replace function public.unblock_user(other_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.friendships
   where status = 'blocked' and requester_id = auth.uid() and addressee_id = other_id;
end;
$$;

create or replace function public.my_friends()
returns setof public.profiles
language sql
stable
security definer
set search_path = public
as $$
  select pr.*
    from public.friendships f
    join public.profiles pr
      on pr.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
   where f.status = 'accepted'
     and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
   order by pr.display_name;
$$;

create or replace function public.my_blocked_users()
returns setof public.profiles
language sql
stable
security definer
set search_path = public
as $$
  select pr.*
    from public.friendships f
    join public.profiles pr on pr.id = f.addressee_id
   where f.status = 'blocked' and f.requester_id = auth.uid()
   order by pr.display_name;
$$;

-- Delete, not deactivate. Everything cascades from auth.users, so this is one
-- statement and there is nothing left behind to un-delete.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    return;
  end if;
  delete from auth.users where id = me;
end;
$$;

-- Expired pings are removed, not archived. Every five minutes rather than
-- nightly: a row that is invisible is still a row, and there is no reason to
-- keep it for the rest of the day.
create or replace function public.purge_expired_pings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.pings where expires_at <= now();
  get diagnostics removed = row_count;
  return removed;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke all on function public.generate_friend_code() from public;
revoke all on function public.delete_my_account() from public;
revoke all on function public.purge_expired_pings() from public;

grant execute on function public.request_friend_by_code(text) to authenticated;
grant execute on function public.accept_friend_request(uuid)  to authenticated;
grant execute on function public.remove_friend(uuid)          to authenticated;
grant execute on function public.block_user(uuid)             to authenticated;
grant execute on function public.unblock_user(uuid)           to authenticated;
grant execute on function public.my_friends()                 to authenticated;
grant execute on function public.my_blocked_users()           to authenticated;
grant execute on function public.delete_my_account()          to authenticated;
grant execute on function public.are_friends(uuid, uuid)      to authenticated;
grant execute on function public.has_pending_between(uuid, uuid) to authenticated;
grant execute on function public.is_blocked_between(uuid, uuid)  to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime and scheduled cleanup
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pings'
  ) then
    alter publication supabase_realtime add table public.pings;
  end if;
end
$$;

-- Requires the pg_cron extension, enabled from the Supabase dashboard.
-- select cron.schedule('purge-expired-pings', '*/5 * * * *',
--                      $$ select public.purge_expired_pings(); $$);
