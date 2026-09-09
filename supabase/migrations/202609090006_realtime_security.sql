-- GG Messenger: production Realtime authorization
-- Private channels are authorized through conversation membership / call participants.

create index if not exists conversation_members_conversation_user_idx
  on public.conversation_members (conversation_id, user_id);

create index if not exists call_sessions_conversation_idx
  on public.call_sessions (conversation_id);

create index if not exists call_sessions_participants_idx
  on public.call_sessions (caller_id, callee_id);

-- Typing channels: typing:<conversation_id>
drop policy if exists "GG members can receive typing broadcasts" on realtime.messages;
create policy "GG members can receive typing broadcasts"
on realtime.messages for select
to authenticated
using (
  extension = 'broadcast'
  and realtime.topic() like 'typing:%'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "GG members can send typing broadcasts" on realtime.messages;
create policy "GG members can send typing broadcasts"
on realtime.messages for insert
to authenticated
with check (
  extension = 'broadcast'
  and realtime.topic() like 'typing:%'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);

-- Call invitation channels: call-invite:<conversation_id>
drop policy if exists "GG members can receive call invites" on realtime.messages;
create policy "GG members can receive call invites"
on realtime.messages for select
to authenticated
using (
  extension = 'broadcast'
  and realtime.topic() like 'call-invite:%'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "GG members can send call invites" on realtime.messages;
create policy "GG members can send call invites"
on realtime.messages for insert
to authenticated
with check (
  extension = 'broadcast'
  and realtime.topic() like 'call-invite:%'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id::text = split_part(realtime.topic(), ':', 2)
      and cm.user_id = auth.uid()
  )
);

-- WebRTC signaling channels: call:<call_session_id>
drop policy if exists "Call participants can receive signaling" on realtime.messages;
create policy "Call participants can receive signaling"
on realtime.messages for select
to authenticated
using (
  extension = 'broadcast'
  and realtime.topic() like 'call:%'
  and exists (
    select 1
    from public.call_sessions cs
    where cs.id::text = split_part(realtime.topic(), ':', 2)
      and (cs.caller_id = auth.uid() or cs.callee_id = auth.uid())
  )
);

drop policy if exists "Call participants can send signaling" on realtime.messages;
create policy "Call participants can send signaling"
on realtime.messages for insert
to authenticated
with check (
  extension = 'broadcast'
  and realtime.topic() like 'call:%'
  and exists (
    select 1
    from public.call_sessions cs
    where cs.id::text = split_part(realtime.topic(), ':', 2)
      and (cs.caller_id = auth.uid() or cs.callee_id = auth.uid())
  )
);

-- Global presence is private, but the presence topic itself is intentionally shared
-- so users can discover online state. Individual chat visibility is still enforced
-- by the UI/data layer.
drop policy if exists "Authenticated users can receive global presence" on realtime.messages;
create policy "Authenticated users can receive global presence"
on realtime.messages for select
to authenticated
using (extension = 'presence' and realtime.topic() = 'global:presence');

drop policy if exists "Authenticated users can publish global presence" on realtime.messages;
create policy "Authenticated users can publish global presence"
on realtime.messages for insert
to authenticated
with check (extension = 'presence' and realtime.topic() = 'global:presence');
