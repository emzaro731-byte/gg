-- GG Messenger: per-user inbox preferences (pin/archive/mute)
create table if not exists public.conversation_user_preferences (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_pinned boolean not null default false,
  is_archived boolean not null default false,
  is_muted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index if not exists conversation_user_preferences_user_idx
  on public.conversation_user_preferences(user_id, is_pinned desc, is_archived, updated_at desc);

alter table public.conversation_user_preferences enable row level security;

drop policy if exists "users can view their conversation preferences" on public.conversation_user_preferences;
create policy "users can view their conversation preferences"
  on public.conversation_user_preferences for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "users can insert their conversation preferences" on public.conversation_user_preferences;
create policy "users can insert their conversation preferences"
  on public.conversation_user_preferences for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = conversation_user_preferences.conversation_id
        and cm.user_id = auth.uid()
    )
  );

drop policy if exists "users can update their conversation preferences" on public.conversation_user_preferences;
create policy "users can update their conversation preferences"
  on public.conversation_user_preferences for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can delete their conversation preferences" on public.conversation_user_preferences;
create policy "users can delete their conversation preferences"
  on public.conversation_user_preferences for delete to authenticated
  using (user_id = auth.uid());

create or replace function public.set_conversation_preference(
  target_conversation_id uuid,
  target_pinned boolean default null,
  target_archived boolean default null,
  target_muted boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = target_conversation_id and cm.user_id = caller
  ) then raise exception 'Conversation not accessible'; end if;

  insert into public.conversation_user_preferences(conversation_id, user_id, is_pinned, is_archived, is_muted)
  values (
    target_conversation_id,
    caller,
    coalesce(target_pinned, false),
    coalesce(target_archived, false),
    coalesce(target_muted, false)
  )
  on conflict (conversation_id, user_id) do update
  set is_pinned = coalesce(target_pinned, conversation_user_preferences.is_pinned),
      is_archived = coalesce(target_archived, conversation_user_preferences.is_archived),
      is_muted = coalesce(target_muted, conversation_user_preferences.is_muted),
      updated_at = now();
end;
$$;

grant execute on function public.set_conversation_preference(uuid, boolean, boolean, boolean) to authenticated;
