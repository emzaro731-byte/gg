-- Allow authenticated conversation members to exchange short-lived call invitations.
-- The actual WebRTC offer/answer/ICE signaling stays protected by call-session RLS.

drop policy if exists "conversation members receive call invites" on realtime.messages;
create policy "conversation members receive call invites"
on realtime.messages for select to authenticated
using (
  extension = 'broadcast'
  and split_part(realtime.topic(), ':', 1) = 'call-invite'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "conversation members send call invites" on realtime.messages;
create policy "conversation members send call invites"
on realtime.messages for insert to authenticated
with check (
  extension = 'broadcast'
  and split_part(realtime.topic(), ':', 1) = 'call-invite'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);
