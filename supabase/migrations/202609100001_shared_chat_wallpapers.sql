-- GG Messenger shared chat wallpapers
-- The wallpaper belongs to the conversation, not to an individual device.

begin;

create table if not exists public.conversation_wallpapers (
  conversation_id uuid primary key references public.conversations(id) on delete cascade,
  wallpaper_key text not null default 'default',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.conversation_wallpapers enable row level security;

drop policy if exists "Members can read conversation wallpaper" on public.conversation_wallpapers;
create policy "Members can read conversation wallpaper"
on public.conversation_wallpapers
for select
to authenticated
using (public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "Members can create conversation wallpaper" on public.conversation_wallpapers;
create policy "Members can create conversation wallpaper"
on public.conversation_wallpapers
for insert
to authenticated
with check (
  public.is_conversation_member(conversation_id, auth.uid())
  and updated_by = auth.uid()
);

drop policy if exists "Members can update conversation wallpaper" on public.conversation_wallpapers;
create policy "Members can update conversation wallpaper"
on public.conversation_wallpapers
for update
to authenticated
using (public.is_conversation_member(conversation_id, auth.uid()))
with check (
  public.is_conversation_member(conversation_id, auth.uid())
  and updated_by = auth.uid()
);

create index if not exists conversation_wallpapers_updated_idx
on public.conversation_wallpapers(updated_at desc);

alter publication supabase_realtime add table public.conversation_wallpapers;

commit;
