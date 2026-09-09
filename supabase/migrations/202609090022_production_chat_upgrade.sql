-- GG Messenger production chat hardening
-- Safe to run after the existing username/chat-power migrations.

begin;

-- ------------------------------------------------------------
-- 1. Keep disappearing-message preferences effective.
--    A new message gets an expiry based on the sender's preference.
-- ------------------------------------------------------------
create or replace function public.apply_disappearing_message_expiry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  seconds integer;
begin
  select cp.disappearing_seconds
    into seconds
  from public.conversation_preferences cp
  where cp.conversation_id = new.conversation_id
    and cp.user_id = coalesce(new.sender_id, auth.uid());

  if seconds is not null and seconds > 0 and new.expires_at is null then
    new.expires_at := now() + make_interval(secs => seconds);
  end if;

  return new;
end;
$$;

drop trigger if exists messages_apply_disappearing_expiry on public.messages;
create trigger messages_apply_disappearing_expiry
before insert on public.messages
for each row execute function public.apply_disappearing_message_expiry();

-- ------------------------------------------------------------
-- 2. Cleanup expired messages when queried by the app.
--    This RPC is member-protected and removes only expired rows.
-- ------------------------------------------------------------
create or replace function public.cleanup_expired_messages(target_conversation_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_conversation_member(target_conversation_id, auth.uid()) then
    raise exception 'Not a conversation member';
  end if;

  delete from public.messages
  where conversation_id = target_conversation_id
    and expires_at is not null
    and expires_at <= now();

  get diagnostics removed = row_count;
  return removed;
end;
$$;

grant execute on function public.cleanup_expired_messages(uuid) to authenticated;

-- ------------------------------------------------------------
-- 3. Return a clean public profile by username.
-- ------------------------------------------------------------
create or replace function public.get_profile_by_username(target_username text)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  last_seen timestamptz
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url, p.bio, p.last_seen
  from public.profiles p
  where lower(p.username) = lower(trim(target_username))
  limit 1;
$$;

grant execute on function public.get_profile_by_username(text) to authenticated;

-- ------------------------------------------------------------
-- 4. Make direct-chat lookup deterministic and ensure the
--    conversation title always follows the other participant.
-- ------------------------------------------------------------
create or replace function public.refresh_direct_chat_title(target_conversation_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  other_username text;
  result_title text;
begin
  if caller is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_conversation_member(target_conversation_id, caller) then
    raise exception 'Not a conversation member';
  end if;

  select p.username
    into other_username
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = target_conversation_id
    and cm.user_id <> caller
  order by cm.user_id
  limit 1;

  result_title := case
    when other_username is null or trim(other_username) = '' then 'Chat'
    else '@' || lower(trim(other_username))
  end;

  update public.conversations
  set title = result_title, updated_at = now()
  where id = target_conversation_id
    and is_group = false;

  return result_title;
end;
$$;

grant execute on function public.refresh_direct_chat_title(uuid) to authenticated;

-- ------------------------------------------------------------
-- 5. Helpful index for chat/message loading.
-- ------------------------------------------------------------
create index if not exists messages_conversation_created_idx
on public.messages(conversation_id, created_at desc);

create index if not exists conversation_members_user_conversation_idx
on public.conversation_members(user_id, conversation_id);

commit;
