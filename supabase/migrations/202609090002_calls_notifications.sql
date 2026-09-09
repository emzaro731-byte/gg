-- GG Messenger: call signaling + notification-ready data model
create table if not exists public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  caller_id uuid not null references auth.users(id) on delete cascade,
  callee_id uuid references auth.users(id) on delete cascade,
  kind text not null default 'voice' check (kind in ('voice','video')),
  status text not null default 'ringing' check (status in ('ringing','accepted','declined','ended','missed')),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists call_sessions_conversation_idx on public.call_sessions(conversation_id, created_at desc);
create index if not exists call_sessions_callee_idx on public.call_sessions(callee_id, created_at desc);

alter table public.call_sessions enable row level security;

drop policy if exists "call members can read sessions" on public.call_sessions;
create policy "call members can read sessions" on public.call_sessions for select to authenticated using (
  caller_id = auth.uid() or callee_id = auth.uid() or exists (
    select 1 from public.conversation_members m
    where m.conversation_id = call_sessions.conversation_id and m.user_id = auth.uid()
  )
);

drop policy if exists "users can create calls" on public.call_sessions;
create policy "users can create calls" on public.call_sessions for insert to authenticated with check (
  caller_id = auth.uid() and exists (
    select 1 from public.conversation_members m
    where m.conversation_id = call_sessions.conversation_id and m.user_id = auth.uid()
  )
);

drop policy if exists "call participants can update calls" on public.call_sessions;
create policy "call participants can update calls" on public.call_sessions for update to authenticated using (
  caller_id = auth.uid() or callee_id = auth.uid()
) with check (caller_id = auth.uid() or callee_id = auth.uid());

-- Device tokens are intentionally separated from auth.users so push providers can be rotated safely.
create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  push_token text not null unique,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);

create index if not exists user_devices_user_idx on public.user_devices(user_id);
alter table public.user_devices enable row level security;

drop policy if exists "users manage own devices" on public.user_devices;
create policy "users manage own devices" on public.user_devices for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Keep the tables in Realtime for call history/UI updates.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_sessions') then
    alter publication supabase_realtime add table public.call_sessions;
  end if;
end $$;
