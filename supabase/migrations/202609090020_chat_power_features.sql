-- GG Messenger power features: pinned messages, disappearing messages, and per-user chat preferences.

alter table public.messages
  add column if not exists expires_at timestamptz;

create index if not exists messages_expires_at_idx on public.messages(expires_at)
  where expires_at is not null;

create table if not exists public.message_pins (
  message_id uuid primary key references public.messages(id) on delete cascade,
  pinned_by uuid not null references auth.users(id) on delete cascade,
  pinned_at timestamptz not null default now()
);

create table if not exists public.conversation_preferences (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  disappearing_seconds integer not null default 0 check (disappearing_seconds >= 0 and disappearing_seconds <= 604800),
  wallpaper text,
  muted_until timestamptz,
  primary key (conversation_id, user_id)
);

create index if not exists message_pins_pinned_by_idx on public.message_pins(pinned_by);

alter table public.message_pins enable row level security;
alter table public.conversation_preferences enable row level security;

create policy "members can read pins" on public.message_pins
for select to authenticated
using (public.is_conversation_member((select conversation_id from public.messages where id = message_id), auth.uid()));

create policy "members can pin messages" on public.message_pins
for insert to authenticated
with check (
  pinned_by = auth.uid()
  and public.is_conversation_member((select conversation_id from public.messages where id = message_id), auth.uid())
);

create policy "pin owner can remove" on public.message_pins
for delete to authenticated
using (pinned_by = auth.uid());

create policy "users can read own chat preferences" on public.conversation_preferences
for select to authenticated using (user_id = auth.uid());

create policy "users can create own chat preferences" on public.conversation_preferences
for insert to authenticated with check (user_id = auth.uid());

create policy "users can update own chat preferences" on public.conversation_preferences
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.set_disappearing_messages(target_conversation_id uuid, seconds integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if seconds < 0 or seconds > 604800 then raise exception 'Invalid disappearing-message duration'; end if;
  if not public.is_conversation_member(target_conversation_id, auth.uid()) then raise exception 'Not a conversation member'; end if;
  insert into public.conversation_preferences(conversation_id, user_id, disappearing_seconds)
  values (target_conversation_id, auth.uid(), seconds)
  on conflict (conversation_id, user_id) do update
    set disappearing_seconds = excluded.disappearing_seconds;
end;
$$;
grant execute on function public.set_disappearing_messages(uuid, integer) to authenticated;

create or replace function public.pin_message(target_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select conversation_id into cid from public.messages where id = target_message_id;
  if cid is null or not public.is_conversation_member(cid, auth.uid()) then raise exception 'Message not accessible'; end if;
  insert into public.message_pins(message_id, pinned_by) values (target_message_id, auth.uid())
  on conflict (message_id) do update set pinned_by = excluded.pinned_by, pinned_at = now();
end;
$$;
grant execute on function public.pin_message(uuid) to authenticated;

create or replace function public.unpin_message(target_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  delete from public.message_pins where message_id = target_message_id and pinned_by = auth.uid();
end;
$$;
grant execute on function public.unpin_message(uuid) to authenticated;
