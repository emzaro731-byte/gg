-- GG Messenger: WhatsApp-style 24-hour statuses
create table if not exists public.statuses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  media_path text,
  media_type text not null default 'text' check (media_type in ('text','image','video')),
  caption text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint status_content_check check (
    (media_path is not null and media_type in ('image','video'))
    or (media_path is null and media_type = 'text' and nullif(trim(caption), '') is not null)
  )
);

create index if not exists statuses_expires_at_idx on public.statuses (expires_at desc);
create index if not exists statuses_user_created_idx on public.statuses (user_id, created_at desc);

alter table public.statuses enable row level security;

drop policy if exists "Users can view active statuses" on public.statuses;
create policy "Users can view active statuses"
on public.statuses for select
to authenticated
using (expires_at > now());

drop policy if exists "Users can create their own statuses" on public.statuses;
create policy "Users can create their own statuses"
on public.statuses for insert
to authenticated
with check (auth.uid() = user_id and expires_at <= now() + interval '24 hours' and expires_at > now());

drop policy if exists "Users can update their own statuses" on public.statuses;
create policy "Users can update their own statuses"
on public.statuses for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own statuses" on public.statuses;
create policy "Users can delete their own statuses"
on public.statuses for delete
to authenticated
using (auth.uid() = user_id);

-- Private bucket for status media; clients receive short-lived signed URLs.
insert into storage.buckets (id, name, public)
values ('status-media', 'status-media', false)
on conflict (id) do update set public = false;

drop policy if exists "Status owners can upload media" on storage.objects;
create policy "Status owners can upload media"
on storage.objects for insert
to authenticated
with check (bucket_id = 'status-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Authenticated users can read status media" on storage.objects;
create policy "Authenticated users can read status media"
on storage.objects for select
to authenticated
using (bucket_id = 'status-media');

drop policy if exists "Status owners can delete media" on storage.objects;
create policy "Status owners can delete media"
on storage.objects for delete
to authenticated
using (bucket_id = 'status-media' and (storage.foldername(name))[1] = auth.uid()::text);

alter publication supabase_realtime add table public.statuses;
