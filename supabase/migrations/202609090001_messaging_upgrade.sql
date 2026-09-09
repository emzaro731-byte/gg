-- GG Messenger messaging upgrade
-- Run this migration after supabase/schema.sql.

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (char_length(reaction) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, reaction)
);

create table if not exists public.message_reads (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists message_reactions_message_idx on public.message_reactions(message_id);
create index if not exists message_reads_message_idx on public.message_reads(message_id);

alter table public.message_reactions enable row level security;
alter table public.message_reads enable row level security;

drop policy if exists "members can read reactions" on public.message_reactions;
create policy "members can read reactions" on public.message_reactions
for select to authenticated using (
  exists (
    select 1 from public.messages msg
    join public.conversation_members cm on cm.conversation_id = msg.conversation_id
    where msg.id = message_id and cm.user_id = auth.uid()
  )
);

drop policy if exists "members can add reactions" on public.message_reactions;
create policy "members can add reactions" on public.message_reactions
for insert to authenticated with check (
  user_id = auth.uid() and exists (
    select 1 from public.messages msg
    join public.conversation_members cm on cm.conversation_id = msg.conversation_id
    where msg.id = message_id and cm.user_id = auth.uid()
  )
);

drop policy if exists "users can remove own reactions" on public.message_reactions;
create policy "users can remove own reactions" on public.message_reactions
for delete to authenticated using (user_id = auth.uid());

drop policy if exists "members can read message receipts" on public.message_reads;
create policy "members can read message receipts" on public.message_reads
for select to authenticated using (
  exists (
    select 1 from public.messages msg
    join public.conversation_members cm on cm.conversation_id = msg.conversation_id
    where msg.id = message_id and cm.user_id = auth.uid()
  )
);

drop policy if exists "users can mark messages read" on public.message_reads;
create policy "users can mark messages read" on public.message_reads
for insert to authenticated with check (
  user_id = auth.uid() and exists (
    select 1 from public.messages msg
    join public.conversation_members cm on cm.conversation_id = msg.conversation_id
    where msg.id = message_id and cm.user_id = auth.uid()
  )
);

drop policy if exists "users can update own read receipts" on public.message_reads;
create policy "users can update own read receipts" on public.message_reads
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Safely create or reuse a direct conversation. This also guarantees the caller is a member.
create or replace function public.create_direct_conversation(target_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  existing_id uuid;
  new_id uuid;
begin
  if caller is null then raise exception 'Not authenticated'; end if;
  if target_user_id is null or target_user_id = caller then raise exception 'Invalid target user'; end if;

  select c.id into existing_id
  from public.conversations c
  where c.is_group = false
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = caller)
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = target_user_id)
  order by c.created_at
  limit 1;

  if existing_id is not null then return existing_id; end if;

  insert into public.conversations(title, is_group, created_by)
  values ('Direct chat', false, caller)
  returning id into new_id;

  insert into public.conversation_members(conversation_id, user_id, role)
  values (new_id, caller, 'member'), (new_id, target_user_id, 'member');

  return new_id;
end;
$$;

grant execute on function public.create_direct_conversation(uuid) to authenticated;

-- Keep the conversation preview current whenever a message is sent or edited.
create or replace function public.touch_conversation_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
  set last_message = case when new.message_type = 'text' then coalesce(new.body, '') else '[' || new.message_type || ']' end,
      updated_at = coalesce(new.created_at, now())
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists messages_touch_conversation on public.messages;
create trigger messages_touch_conversation
after insert on public.messages
for each row execute procedure public.touch_conversation_from_message();

-- Realtime for the new tables. Ignore duplicate publication entries.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_reads'
  ) then
    alter publication supabase_realtime add table public.message_reads;
  end if;
end $$;
