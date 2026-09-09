-- GG Messenger database foundation
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null default 'GG User',
  avatar_url text,
  bio text,
  last_seen timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  title text,
  is_group boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  last_message text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  role text not null default 'member',
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text,
  message_type text not null default 'text',
  media_url text,
  reply_to uuid references public.messages(id) on delete set null,
  edited_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists messages_conversation_created_idx on public.messages(conversation_id, created_at desc);
create index if not exists members_user_idx on public.conversation_members(user_id);

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

create policy "profiles are readable" on public.profiles for select to authenticated using (true);
create policy "users create own profile" on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy "users update own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create policy "members can read conversations" on public.conversations for select to authenticated using (exists (select 1 from public.conversation_members m where m.conversation_id = id and m.user_id = auth.uid()));
create policy "authenticated users can create conversations" on public.conversations for insert to authenticated with check (auth.uid() = created_by);
create policy "members can read membership" on public.conversation_members for select to authenticated using (user_id = auth.uid() or exists (select 1 from public.conversation_members m where m.conversation_id = conversation_id and m.user_id = auth.uid()));
create policy "users can join conversations" on public.conversation_members for insert to authenticated with check (user_id = auth.uid());

create policy "members can read messages" on public.messages for select to authenticated using (exists (select 1 from public.conversation_members m where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));
create policy "members can send messages" on public.messages for insert to authenticated with check (sender_id = auth.uid() and exists (select 1 from public.conversation_members m where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));
create policy "senders can edit messages" on public.messages for update to authenticated using (sender_id = auth.uid()) with check (sender_id = auth.uid());
create policy "senders can delete messages" on public.messages for delete to authenticated using (sender_id = auth.uid());

-- Enable Realtime for live messenger updates.
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.profiles;

-- Automatically create a profile when a user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'GG User'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();
