-- GG Messenger: pinned messages
create table if not exists public.conversation_pins (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  pinned_by uuid not null references auth.users(id) on delete cascade,
  pinned_at timestamptz not null default now(),
  primary key (conversation_id, message_id)
);

create index if not exists conversation_pins_conversation_idx
  on public.conversation_pins(conversation_id, pinned_at desc);

alter table public.conversation_pins enable row level security;

drop policy if exists "members can view conversation pins" on public.conversation_pins;
create policy "members can view conversation pins"
  on public.conversation_pins for select to authenticated
  using (exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = conversation_pins.conversation_id
      and cm.user_id = auth.uid()
  ));

drop policy if exists "members can pin messages" on public.conversation_pins;
create policy "members can pin messages"
  on public.conversation_pins for insert to authenticated
  with check (
    pinned_by = auth.uid()
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = conversation_pins.conversation_id
        and cm.user_id = auth.uid()
    )
    and exists (
      select 1 from public.messages m
      where m.id = conversation_pins.message_id
        and m.conversation_id = conversation_pins.conversation_id
    )
  );

drop policy if exists "pinners can remove conversation pins" on public.conversation_pins;
create policy "pinners can remove conversation pins"
  on public.conversation_pins for delete to authenticated
  using (pinned_by = auth.uid() or exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = conversation_pins.conversation_id
      and cm.user_id = auth.uid()
      and cm.role = 'admin'
  ));

create or replace function public.pin_message(target_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_id_value uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;

  select m.conversation_id into conversation_id_value
  from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id
  where m.id = target_message_id and cm.user_id = auth.uid();

  if conversation_id_value is null then raise exception 'Message not accessible'; end if;

  insert into public.conversation_pins(conversation_id, message_id, pinned_by)
  values (conversation_id_value, target_message_id, auth.uid())
  on conflict (conversation_id, message_id) do nothing;
end;
$$;

grant execute on function public.pin_message(uuid) to authenticated;

create or replace function public.unpin_message(target_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;

  delete from public.conversation_pins p
  where p.message_id = target_message_id
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = p.conversation_id
        and cm.user_id = auth.uid()
    );
end;
$$;

grant execute on function public.unpin_message(uuid) to authenticated;
