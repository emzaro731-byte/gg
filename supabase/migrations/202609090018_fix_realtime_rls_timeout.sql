-- GG Messenger: fix Realtime subscription timeouts caused by recursive RLS.
-- Run after the existing messaging migrations.

-- SECURITY DEFINER prevents the membership check from recursively invoking
-- conversation_members RLS while Realtime evaluates rows for a subscriber.
create or replace function public.is_conversation_member(target_conversation_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and cm.user_id = target_user_id
  );
$$;

revoke all on function public.is_conversation_member(uuid, uuid) from public;
grant execute on function public.is_conversation_member(uuid, uuid) to authenticated;

-- Remove the recursive policies from the original schema/migrations.
drop policy if exists "members can read conversations" on public.conversations;
drop policy if exists "members can read membership" on public.conversation_members;
drop policy if exists "members can read messages" on public.messages;
drop policy if exists "members can send messages" on public.messages;
drop policy if exists "users can insert own chat settings" on public.conversation_user_settings;

create policy "members can read conversations"
on public.conversations
for select to authenticated
using (public.is_conversation_member(id, auth.uid()));

create policy "members can read membership"
on public.conversation_members
for select to authenticated
using (
  user_id = auth.uid()
  or public.is_conversation_member(conversation_id, auth.uid())
);

create policy "members can read messages"
on public.messages
for select to authenticated
using (public.is_conversation_member(conversation_id, auth.uid()));

create policy "members can send messages"
on public.messages
for insert to authenticated
with check (
  sender_id = auth.uid()
  and public.is_conversation_member(conversation_id, auth.uid())
);

-- conversation_user_settings is optional in older deployments, so only alter
-- it when the table exists.
do $$
begin
  if to_regclass('public.conversation_user_settings') is not null then
    execute 'create policy "users can insert own chat settings" on public.conversation_user_settings for insert to authenticated with check (user_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()))';
  end if;
end $$;

-- Ensure all chat tables are in Realtime, without duplicate-object errors.
do $$
declare
  t text;
begin
  foreach t in array array['conversations','conversation_members','messages','conversation_user_settings'] loop
    if to_regclass('public.' || t) is not null
       and not exists (
         select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = t
       ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
