-- GG Messenger: push notification token registry
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android','ios','web')),
  device_name text,
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(user_id, token)
);

create index if not exists push_tokens_user_enabled_idx
  on public.push_tokens(user_id, enabled);

alter table public.push_tokens enable row level security;

drop policy if exists "Users can manage own push tokens" on public.push_tokens;
create policy "Users can manage own push tokens"
  on public.push_tokens for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.push_tokens to authenticated;

create or replace function public.register_push_token(
  device_token text,
  device_platform text,
  device_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare token_id uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(device_token), '') is null then raise exception 'Push token is required'; end if;
  if device_platform not in ('android','ios','web') then raise exception 'Unsupported platform'; end if;

  insert into public.push_tokens(user_id, token, platform, device_name, enabled, last_seen_at)
  values (auth.uid(), trim(device_token), device_platform, nullif(trim(device_name), ''), true, now())
  on conflict (user_id, token) do update set
    platform = excluded.platform,
    device_name = excluded.device_name,
    enabled = true,
    last_seen_at = now()
  returning id into token_id;

  return token_id;
end;
$$;

grant execute on function public.register_push_token(text, text, text) to authenticated;

create or replace function public.disable_push_token(device_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  update public.push_tokens
  set enabled = false, last_seen_at = now()
  where user_id = auth.uid() and token = trim(device_token);
end;
$$;

grant execute on function public.disable_push_token(text) to authenticated;
