-- GG Messenger: status views and reactions

create table if not exists public.status_views (
  status_id uuid not null references public.statuses(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (status_id, viewer_id)
);

create table if not exists public.status_reactions (
  status_id uuid not null references public.statuses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (char_length(reaction) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (status_id, user_id)
);

create index if not exists status_views_status_idx on public.status_views(status_id, viewed_at desc);
create index if not exists status_views_viewer_idx on public.status_views(viewer_id, viewed_at desc);
create index if not exists status_reactions_status_idx on public.status_reactions(status_id, created_at desc);

alter table public.status_views enable row level security;
alter table public.status_reactions enable row level security;

drop policy if exists "Authenticated users can read status views" on public.status_views;
create policy "Authenticated users can read status views"
on public.status_views for select to authenticated
using (exists (
  select 1 from public.statuses s
  where s.id = status_id and (s.user_id = auth.uid() or exists (
    select 1 from public.status_views own_view
    where own_view.status_id = s.id and own_view.viewer_id = auth.uid()
  ))
));

drop policy if exists "Users can record status views" on public.status_views;
create policy "Users can record status views"
on public.status_views for insert to authenticated
with check (
  viewer_id = auth.uid()
  and exists (select 1 from public.statuses s where s.id = status_id and s.expires_at > now())
);

drop policy if exists "Users can update own status views" on public.status_views;
create policy "Users can update own status views"
on public.status_views for update to authenticated
using (viewer_id = auth.uid()) with check (viewer_id = auth.uid());

drop policy if exists "Authenticated users can read status reactions" on public.status_reactions;
create policy "Authenticated users can read status reactions"
on public.status_reactions for select to authenticated
using (exists (select 1 from public.statuses s where s.id = status_id and s.expires_at > now()));

drop policy if exists "Users can react to active statuses" on public.status_reactions;
create policy "Users can react to active statuses"
on public.status_reactions for insert to authenticated
with check (user_id = auth.uid() and exists (
  select 1 from public.statuses s where s.id = status_id and s.expires_at > now()
));

drop policy if exists "Users can update own status reactions" on public.status_reactions;
create policy "Users can update own status reactions"
on public.status_reactions for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Users can delete own status reactions" on public.status_reactions;
create policy "Users can delete own status reactions"
on public.status_reactions for delete to authenticated
using (user_id = auth.uid());

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'status_views') then
    alter publication supabase_realtime add table public.status_views;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'status_reactions') then
    alter publication supabase_realtime add table public.status_reactions;
  end if;
end $$;
