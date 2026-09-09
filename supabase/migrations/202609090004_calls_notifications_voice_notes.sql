-- GG Messenger: calls, push tokens and voice-note metadata

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'flutter',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

alter table public.device_tokens enable row level security;
drop policy if exists "users manage own device tokens" on public.device_tokens;
create policy "users manage own device tokens"
on public.device_tokens for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

alter table public.messages
  add column if not exists duration_ms integer;

create index if not exists device_tokens_user_idx on public.device_tokens(user_id);
create index if not exists messages_audio_idx on public.messages(conversation_id, message_type, created_at desc);

create table if not exists public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  caller_id uuid not null references auth.users(id) on delete cascade,
  callee_id uuid not null references auth.users(id) on delete cascade,
  call_type text not null check (call_type in ('audio','video')),
  status text not null default 'ringing' check (status in ('ringing','accepted','rejected','ended','missed')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz
);

create index if not exists call_sessions_callee_idx on public.call_sessions(callee_id, created_at desc);
create index if not exists call_sessions_caller_idx on public.call_sessions(caller_id, created_at desc);

alter table public.call_sessions enable row level security;
drop policy if exists "conversation members can read calls" on public.call_sessions;
create policy "conversation members can read calls"
on public.call_sessions for select to authenticated
using (exists (
  select 1 from public.conversation_members cm
  where cm.conversation_id = call_sessions.conversation_id
    and cm.user_id = auth.uid()
));

drop policy if exists "members can create own calls" on public.call_sessions;
create policy "members can create own calls"
on public.call_sessions for insert to authenticated
with check (
  caller_id = auth.uid()
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = call_sessions.conversation_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "call participants can update calls" on public.call_sessions;
create policy "call participants can update calls"
on public.call_sessions for update to authenticated
using (caller_id = auth.uid() or callee_id = auth.uid())
with check (caller_id = auth.uid() or callee_id = auth.uid());

-- Broadcast signaling is intentionally transient: offers, answers and ICE candidates
-- should not be persisted as message content.
drop policy if exists "call members receive signaling" on realtime.messages;
create policy "call members receive signaling"
on realtime.messages for select to authenticated
using (
  extension = 'broadcast'
  and split_part(realtime.topic(), ':', 1) = 'call'
  and exists (
    select 1 from public.call_sessions cs
    where cs.id::text = split_part(realtime.topic(), ':', 2)
      and (cs.caller_id = auth.uid() or cs.callee_id = auth.uid())
  )
);

drop policy if exists "call members send signaling" on realtime.messages;
create policy "call members send signaling"
on realtime.messages for insert to authenticated
with check (
  extension = 'broadcast'
  and split_part(realtime.topic(), ':', 1) = 'call'
  and exists (
    select 1 from public.call_sessions cs
    where cs.id::text = split_part(realtime.topic(), ':', 2)
      and (cs.caller_id = auth.uid() or cs.callee_id = auth.uid())
  )
);
