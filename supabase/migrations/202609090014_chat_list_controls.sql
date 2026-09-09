-- GG Messenger: per-user inbox controls (pin, archive, mute)
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

create or replace function public.set_conversation_list_state(
  target_conversation_id uuid,
  pin_state boolean default null,
  archive_state boolean default null,
  mute_until_value timestamptz default null,
  clear_mute boolean default false
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
    select 1 from public.conversation_members
    where conversation_id = target_conversation_id and user_id = caller
  ) then raise exception 'Conversation not accessible'; end if;

  insert into public.conversation_user_settings(conversation_id, user_id)
  values (target_conversation_id, caller)
  on conflict (conversation_id, user_id) do nothing;

  update public.conversation_user_settings
  set pinned_at = case
        when pin_state is true then coalesce(pinned_at, now())
        when pin_state is false then null
        else pinned_at
      end,
      archived_at = case
        when archive_state is true then coalesce(archived_at, now())
        when archive_state is false then null
        else archived_at
      end,
      muted_until = case
        when clear_mute then null
        when mute_until_value is not null then mute_until_value
        else muted_until
      end,
      updated_at = now()
  where conversation_id = target_conversation_id and user_id = caller;
end;
$$;

grant execute on function public.set_conversation_list_state(uuid, boolean, boolean, timestamptz, boolean) to authenticated;
