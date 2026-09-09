-- GG Messenger: required, globally unique usernames + username search support
update public.profiles set username = lower(trim(username)) where username is not null;
update public.profiles set username = null where username is not null and trim(username) = '';

create unique index if not exists profiles_username_lower_unique on public.profiles (lower(username)) where username is not null;

alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format check (username is null or username ~ '^[a-z0-9_.]{3,30}$');
create index if not exists profiles_username_lower_search_idx on public.profiles (lower(username));

-- Create the profile from signup metadata, including the required username.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  requested_username text := lower(trim(coalesce(new.raw_user_meta_data->>'username', '')));
  requested_name text := trim(coalesce(new.raw_user_meta_data->>'display_name', 'GG User'));
begin
  if requested_username = '' then raise exception 'Username is required.'; end if;
  if requested_username !~ '^[a-z0-9_.]{3,30}$' then raise exception 'Username must be 3-30 characters and contain only letters, numbers, underscores or dots.'; end if;
  insert into public.profiles (id, username, display_name)
  values (new.id, requested_username, coalesce(nullif(requested_name, ''), 'GG User'))
  on conflict (id) do update set username = excluded.username, display_name = excluded.display_name, updated_at = now();
  return new;
exception when unique_violation then raise exception 'That username is already taken.';
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

grant execute on function public.handle_new_user() to service_role;

create or replace function public.reserve_username(requested_username text)
returns text language plpgsql security definer set search_path = public
as $$
declare normalized text := lower(trim(requested_username)); existing_user uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if normalized !~ '^[a-z0-9_.]{3,30}$' then raise exception 'Username must be 3-30 characters and contain only letters, numbers, underscores or dots.'; end if;
  select id into existing_user from public.profiles where lower(username) = normalized limit 1;
  if existing_user is not null and existing_user <> auth.uid() then raise exception 'That username is already taken.'; end if;
  update public.profiles set username = normalized, updated_at = now() where id = auth.uid();
  if not found then insert into public.profiles (id, username, display_name, updated_at) values (auth.uid(), normalized, 'GG User', now()); end if;
  return normalized;
exception when unique_violation then raise exception 'That username is already taken.';
end;
$$;

grant execute on function public.reserve_username(text) to authenticated;

create or replace function public.search_users_by_username(search_username text, result_limit integer default 30)
returns table (id uuid, username text, display_name text, avatar_url text, bio text, last_seen timestamptz)
language sql security invoker stable
as $$
  select p.id, p.username, p.display_name, p.avatar_url, p.bio, p.last_seen
  from public.profiles p
  where p.id <> auth.uid() and p.username is not null and lower(p.username) like '%' || lower(trim(search_username)) || '%'
  order by case when lower(p.username) = lower(trim(search_username)) then 0 else 1 end, lower(p.username)
  limit greatest(1, least(coalesce(result_limit, 30), 50));
$$;

grant execute on function public.search_users_by_username(text, integer) to authenticated;
