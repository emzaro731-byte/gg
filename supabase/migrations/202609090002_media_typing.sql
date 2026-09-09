-- GG Messenger media + realtime upgrade

create extension if not exists pgcrypto;

-- Media files are stored in the Supabase Storage bucket `chat-media`.
-- The app records only metadata/path in messages.

alter table public.messages
  add column if not exists file_name text,
  add column if not exists file_size bigint,
  add column if not exists mime_type text;

create index if not exists messages_type_idx
  on public.messages(conversation_id, message_type, created_at desc);

-- Private bucket for chat attachments.
insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

-- Storage policies are limited to authenticated users. Conversation-level
-- authorization for a production deployment should be tightened further
-- using a storage object naming convention or an Edge Function.
drop policy if exists "chat media authenticated upload" on storage.objects;
create policy "chat media authenticated upload"
on storage.objects for insert to authenticated
with check (bucket_id = 'chat-media');

drop policy if exists "chat media authenticated read" on storage.objects;
create policy "chat media authenticated read"
on storage.objects for select to authenticated
using (bucket_id = 'chat-media');

drop policy if exists "chat media owner delete" on storage.objects;
create policy "chat media owner delete"
on storage.objects for delete to authenticated
using (bucket_id = 'chat-media' and owner_id = auth.uid()::text);

-- Make typing broadcasts private when Realtime authorization is enabled.
-- Channel topic format: typing:<conversation_id>

drop policy if exists "chat members can receive typing" on realtime.messages;
create policy "chat members can receive typing"
on realtime.messages for select to authenticated
using (
  extension = 'broadcast'
  and split_part(realtime.topic(), ':', 1) = 'typing'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "chat members can send typing" on realtime.messages;
create policy "chat members can send typing"
on realtime.messages for insert to authenticated
with check (
  extension = 'broadcast'
  and split_part(realtime.topic(), ':', 1) = 'typing'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);
