-- Every profile username is a unique public handle.
-- Case-insensitive uniqueness means @John and @john cannot both exist.

create unique index if not exists profiles_username_unique_idx
on public.profiles (lower(username))
where username is not null and btrim(username) <> '';

alter table public.profiles
  drop constraint if exists profiles_username_format_check;

alter table public.profiles
  add constraint profiles_username_format_check
  check (
    username is null
    or username ~ '^[a-z0-9_\.]{3,30}$'
  );
