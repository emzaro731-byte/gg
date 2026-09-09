-- Replace the generic Direct chat title with the other user's username.
create or replace function public.sync_direct_chat_username()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.username is distinct from old.username then
    update public.conversations c
    set title = case when new.username is null or trim(new.username) = '' then 'Chat' else '@' || lower(trim(new.username)) end,
        updated_at = now()
    where c.is_group = false
      and exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = c.id and cm.user_id = new.id
      );
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_sync_direct_chat_username on public.profiles;
create trigger profiles_sync_direct_chat_username
after update of username on public.profiles
for each row execute procedure public.sync_direct_chat_username();

-- Backfill existing direct conversations.
update public.conversations c
set title = '@' || lower(trim(p.username))
from public.conversation_members cm
join public.profiles p on p.id = cm.user_id
where c.id = cm.conversation_id
  and c.is_group = false
  and cm.user_id <> c.created_by
  and p.username is not null
  and trim(p.username) <> '';

-- New direct conversations use the target user's username immediately.
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
  target_username text;
begin
  if caller is null then raise exception 'Not authenticated'; end if;
  if target_user_id is null or target_user_id = caller then raise exception 'Invalid target user'; end if;

  select p.username into target_username from public.profiles p where p.id = target_user_id;

  select c.id into existing_id
  from public.conversations c
  where c.is_group = false
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = caller)
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = target_user_id)
  order by c.created_at
  limit 1;

  if existing_id is not null then
    update public.conversations
    set title = case when target_username is null or trim(target_username) = '' then 'Chat' else '@' || lower(trim(target_username)) end
    where id = existing_id;
    return existing_id;
  end if;

  insert into public.conversations(title, is_group, created_by)
  values (case when target_username is null or trim(target_username) = '' then 'Chat' else '@' || lower(trim(target_username)) end, false, caller)
  returning id into new_id;

  insert into public.conversation_members(conversation_id, user_id, role)
  values (new_id, caller, 'member'), (new_id, target_user_id, 'member');

  return new_id;
end;
$$;

grant execute on function public.create_direct_conversation(uuid) to authenticated;
