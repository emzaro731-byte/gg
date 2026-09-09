-- GG Messenger: production group administration controls

create index if not exists conversation_members_conversation_user_idx
  on public.conversation_members(conversation_id, user_id);

create or replace function public.remove_group_member(group_id uuid, member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.conversation_members
    where conversation_id = group_id and user_id = auth.uid() and role = 'admin'
  ) then raise exception 'Only group admins can remove members'; end if;
  if not exists (select 1 from public.conversations where id = group_id and is_group = true) then
    raise exception 'Group not found';
  end if;
  if member_id = auth.uid() then raise exception 'Use leave_group to leave the group'; end if;
  delete from public.conversation_members
  where conversation_id = group_id and user_id = member_id;
end;
$$;

grant execute on function public.remove_group_member(uuid, uuid) to authenticated;

create or replace function public.set_group_admin(group_id uuid, member_id uuid, make_admin boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.conversation_members
    where conversation_id = group_id and user_id = auth.uid() and role = 'admin'
  ) then raise exception 'Only group admins can change admin roles'; end if;
  if not exists (select 1 from public.conversations where id = group_id and is_group = true) then
    raise exception 'Group not found';
  end if;
  if not exists (select 1 from public.conversation_members where conversation_id = group_id and user_id = member_id) then
    raise exception 'Member not found';
  end if;
  update public.conversation_members
  set role = case when make_admin then 'admin' else 'member' end
  where conversation_id = group_id and user_id = member_id;
end;
$$;

grant execute on function public.set_group_admin(uuid, uuid, boolean) to authenticated;

create or replace function public.leave_group(group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  admin_count integer;
  member_count integer;
begin
  if caller is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.conversations where id = group_id and is_group = true) then
    raise exception 'Group not found';
  end if;
  if not exists (select 1 from public.conversation_members where conversation_id = group_id and user_id = caller) then
    raise exception 'You are not a group member';
  end if;

  select count(*) into admin_count from public.conversation_members where conversation_id = group_id and role = 'admin';
  select count(*) into member_count from public.conversation_members where conversation_id = group_id;

  if member_count > 1 and admin_count = 1 and exists (
    select 1 from public.conversation_members where conversation_id = group_id and user_id = caller and role = 'admin'
  ) then
    raise exception 'Promote another admin before leaving';
  end if;

  delete from public.conversation_members where conversation_id = group_id and user_id = caller;
end;
$$;

grant execute on function public.leave_group(uuid) to authenticated;

create or replace function public.update_group_title(group_id uuid, new_title text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare clean_title text := nullif(trim(new_title), '');
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if clean_title is null or char_length(clean_title) > 80 then raise exception 'Group name must be 1-80 characters'; end if;
  if not exists (
    select 1 from public.conversation_members
    where conversation_id = group_id and user_id = auth.uid() and role = 'admin'
  ) then raise exception 'Only group admins can rename the group'; end if;
  update public.conversations set title = clean_title, updated_at = now()
  where id = group_id and is_group = true;
end;
$$;

grant execute on function public.update_group_title(uuid, text) to authenticated;
