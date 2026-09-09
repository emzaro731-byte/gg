-- Secure the global online-presence channel.
-- Realtime Authorization checks these policies when authenticated clients join,
-- listen for presence changes, or publish their own presence state.

create policy "authenticated can read global presence"
on realtime.messages
for select
to authenticated
using (
  realtime.topic() = 'global:presence'
  and realtime.messages.extension = 'presence'
);

create policy "authenticated can publish global presence"
on realtime.messages
for insert
to authenticated
with check (
  realtime.topic() = 'global:presence'
  and realtime.messages.extension = 'presence'
);
