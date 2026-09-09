-- GG Messenger: group chat creation and membership management
create or replace function public.create_group_conversation(group_title text, member_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  new_id uuid;
  clean_title text := nullif(trim(group_title), '');
  member_id uuid;
begin
  if caller is null then raise exception 'Not authenticated'; end if;
  if clean_title is null or char_length(clean_title) > 80 then raise exception 'Group name must be 1-80 characters'; end if;

  insert into public.conversations(title, is_group, created_by)
  values (clean_title, true, caller)
  returning id into new_id;

  insert into public.conversation_members(conversation_id, user_id, role)
  values (new_id, caller, 'admin');

  foreach member_id in array coalesce(member_ids, '{}') loop
    if member_id is not null and member_id <> caller then
      insert into public.conversation_members(conversation_id, user_id, role)
      values (new_id, member_id, 'member')
      on conflict do nothing;
    end if;
  end loop;

  return new_id;
end;
$$;

grant execute on function public.create_group_conversation(text, uuid[]) to authenticated;

create or replace function public.add_group_member(group_id uuid, new_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.conversation_members where conversation_id = group_id and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only group admins can add members';
  end if;
  if not exists (select 1 from public.conversations where id = group_id and is_group = true) then
    raise exception 'Group not found';
  end if;
  insert into public.conversation_members(conversation_id, user_id, role)
  values (group_id, new_member_id, 'member')
  on conflict do nothing;
end;
$$;

grant execute on function public.add_group_member(uuid, uuid) to authenticated;
