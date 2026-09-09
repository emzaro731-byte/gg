-- GG Messenger: simple WhatsApp-style status privacy.
-- everyone = all authenticated users, nobody = owner only.
alter table public.statuses
  add column if not exists visibility text not null default 'everyone';

alter table public.statuses
  drop constraint if exists statuses_visibility_check;

alter table public.statuses
  add constraint statuses_visibility_check
  check (visibility in ('everyone', 'nobody'));

drop policy if exists "Users can view active statuses" on public.statuses;
create policy "Users can view active statuses"
on public.statuses for select
to authenticated
using (
  expires_at > now()
  and (visibility = 'everyone' or user_id = auth.uid())
);
