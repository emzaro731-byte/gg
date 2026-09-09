-- GG Messenger: realtime/chat schema repair
-- Safe to run on databases that are behind the repository migrations.

-- The chat list UI uses this table for per-user pin/archive/mute state.
create table if not exists public.conversation_user_settings (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  pinned_at timestamptz null,
  archived_at timestamptz null,
  muted_until timestamptz null,
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index if not exists conversation_user_settings_user_idx
  on public.conversation_user_settings(user_id, pinned_at desc, archived_at, updated_at desc);

alter table public.conversation_user_settings enable row level security;

drop policy if exists "users can view own chat settings" on public.conversation_user_settings;
create policy "users can view own chat settings"
  on public.conversation_user_settings for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "users can insert own chat settings" on public.conversation_user_settings;
create policy "users can insert own chat settings"
  on public.conversation_user_settings for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = conversation_user_settings.conversation_id
        and cm.user_id = auth.uid()
    )
  );

drop policy if exists "users can update own chat settings" on public.conversation_user_settings;
create policy "users can update own chat settings"
  on public.conversation_user_settings for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can delete own chat settings" on public.conversation_user_settings;
create policy "users can delete own chat settings"
  on public.conversation_user_settings for delete to authenticated
  using (user_id = auth.uid());

-- Repair the Realtime publication without failing when an optional table is absent.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'messages',
    'conversations',
    'conversation_members',
    'conversation_user_settings',
    'call_sessions',
    'notifications',
    'statuses',
    'status_reactions',
    'message_reactions'
  ] LOOP
    IF to_regclass('public.' || t) IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime'
           AND schemaname = 'public'
           AND tablename = t
       ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
