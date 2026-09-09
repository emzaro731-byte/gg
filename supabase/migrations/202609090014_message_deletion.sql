-- GG Messenger: safe soft-delete for messages
alter table public.messages
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create index if not exists messages_deleted_at_idx
  on public.messages(conversation_id, deleted_at, created_at);

create or replace function public.delete_message_for_everyone(target_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  message_sender uuid;
  message_conversation uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;

  select sender_id, conversation_id
    into message_sender, message_conversation
  from public.messages
  where id = target_message_id;

  if message_sender is null then raise exception 'Message not found'; end if;

  if message_sender <> auth.uid() and not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = message_conversation
      and cm.user_id = auth.uid()
      and cm.role = 'admin'
  ) then
    raise exception 'Not allowed to delete this message';
  end if;

  update public.messages
  set deleted_at = coalesce(deleted_at, now()),
      deleted_by = coalesce(deleted_by, auth.uid()),
      body = null,
      media_url = null,
      file_name = null,
      file_size = null,
      mime_type = null
  where id = target_message_id;
end;
$$;

grant execute on function public.delete_message_for_everyone(uuid) to authenticated;
