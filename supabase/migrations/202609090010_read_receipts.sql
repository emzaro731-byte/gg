-- GG Messenger: durable read receipts and unread counters
create table if not exists public.conversation_reads (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_message_id uuid null references public.messages(id) on delete set null,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index if not exists conversation_reads_user_idx
  on public.conversation_reads(user_id, conversation_id);

alter table public.conversation_reads enable row level security;

drop policy if exists "conversation reads are visible to members" on public.conversation_reads;
create policy "conversation reads are visible to members"
on public.conversation_reads for select
to authenticated
using (
  exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = conversation_reads.conversation_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "users can upsert their own read state" on public.conversation_reads;
create policy "users can upsert their own read state"
on public.conversation_reads for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = conversation_reads.conversation_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "users can update their own read state" on public.conversation_reads;
create policy "users can update their own read state"
on public.conversation_reads for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace function public.mark_conversation_read(
  target_conversation_id uuid,
  target_message_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.conversation_members
    where conversation_id = target_conversation_id and user_id = auth.uid()
  ) then
    raise exception 'Not a conversation member';
  end if;

  insert into public.conversation_reads(conversation_id, user_id, last_read_message_id, last_read_at)
  values (target_conversation_id, auth.uid(), target_message_id, now())
  on conflict (conversation_id, user_id)
  do update set
    last_read_message_id = excluded.last_read_message_id,
    last_read_at = excluded.last_read_at;
end;
$$;

grant execute on function public.mark_conversation_read(uuid, uuid) to authenticated;

create or replace function public.get_unread_count(target_conversation_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)
  from public.messages m
  left join public.conversation_reads cr
    on cr.conversation_id = m.conversation_id
   and cr.user_id = auth.uid()
  where m.conversation_id = target_conversation_id
    and m.sender_id <> auth.uid()
    and m.created_at > coalesce(cr.last_read_at, 'epoch'::timestamptz)
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = target_conversation_id and cm.user_id = auth.uid()
    );
$$;

grant execute on function public.get_unread_count(uuid) to authenticated;
