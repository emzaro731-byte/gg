-- GG Messenger: delivery/read receipts and reaction aggregation
alter table public.message_reads add column if not exists delivered_at timestamptz;

create index if not exists message_reads_user_message_idx on public.message_reads(user_id, message_id);

create or replace function public.mark_message_delivered(target_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.messages m
    join public.conversation_members cm on cm.conversation_id = m.conversation_id
    where m.id = target_message_id and cm.user_id = auth.uid()
  ) then raise exception 'Message not accessible'; end if;
  insert into public.message_reads(message_id, user_id, delivered_at)
  values (target_message_id, auth.uid(), now())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(public.message_reads.delivered_at, excluded.delivered_at);
end;
$$;
grant execute on function public.mark_message_delivered(uuid) to authenticated;

create or replace function public.mark_message_read(target_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.messages m
    join public.conversation_members cm on cm.conversation_id = m.conversation_id
    where m.id = target_message_id and cm.user_id = auth.uid()
  ) then raise exception 'Message not accessible'; end if;
  insert into public.message_reads(message_id, user_id, delivered_at, read_at)
  values (target_message_id, auth.uid(), now(), now())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(public.message_reads.delivered_at, excluded.delivered_at),
        read_at = coalesce(public.message_reads.read_at, excluded.read_at);
end;
$$;
grant execute on function public.mark_message_read(uuid) to authenticated;

create or replace function public.get_message_receipt(target_message_id uuid)
returns table(delivered_count bigint, read_count bigint)
language sql security definer set search_path = public as $$
  select count(*) filter (where mr.delivered_at is not null),
         count(*) filter (where mr.read_at is not null)
  from public.message_reads mr where mr.message_id = target_message_id;
$$;
grant execute on function public.get_message_receipt(uuid) to authenticated;

create or replace function public.get_message_reaction_counts(target_message_id uuid)
returns table(reaction text, count bigint)
language sql security definer set search_path = public as $$
  select mr.reaction, count(*)
  from public.message_reactions mr
  where mr.message_id = target_message_id
  group by mr.reaction order by count(*) desc, mr.reaction;
$$;
grant execute on function public.get_message_reaction_counts(uuid) to authenticated;
