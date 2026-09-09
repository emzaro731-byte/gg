-- GG Messenger: durable delivery receipts
create table if not exists public.message_deliveries (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  delivered_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists message_deliveries_user_idx
  on public.message_deliveries(user_id, delivered_at desc);

alter table public.message_deliveries enable row level security;

drop policy if exists "members can read delivery receipts" on public.message_deliveries;
create policy "members can read delivery receipts"
on public.message_deliveries for select
to authenticated
using (
  exists (
    select 1
    from public.messages m
    join public.conversation_members cm on cm.conversation_id = m.conversation_id
    where m.id = message_deliveries.message_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "members can create delivery receipts" on public.message_deliveries;
create policy "members can create delivery receipts"
on public.message_deliveries for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.messages m
    join public.conversation_members cm on cm.conversation_id = m.conversation_id
    where m.id = message_deliveries.message_id
      and cm.user_id = auth.uid()
  )
);

create or replace function public.mark_message_delivered(target_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1
    from public.messages m
    join public.conversation_members cm on cm.conversation_id = m.conversation_id
    where m.id = target_message_id and cm.user_id = auth.uid()
  ) then
    raise exception 'Not a conversation member';
  end if;

  insert into public.message_deliveries(message_id, user_id, delivered_at)
  values (target_message_id, auth.uid(), now())
  on conflict (message_id, user_id) do nothing;
end;
$$;

grant execute on function public.mark_message_delivered(uuid) to authenticated;
