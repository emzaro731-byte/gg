-- GG Messenger: chat + AI like/dislike feedback
create table if not exists public.message_feedback (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  value smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create table if not exists public.ai_feedback (
  conversation_id uuid not null,
  message_index integer not null check (message_index >= 0),
  user_id uuid not null references auth.users(id) on delete cascade,
  value smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, message_index, user_id)
);

create index if not exists message_feedback_message_idx on public.message_feedback(message_id);
create index if not exists ai_feedback_conversation_idx on public.ai_feedback(conversation_id, message_index);

alter table public.message_feedback enable row level security;
alter table public.ai_feedback enable row level security;

drop policy if exists "Users can read message feedback" on public.message_feedback;
create policy "Users can read message feedback" on public.message_feedback
for select to authenticated using (true);

drop policy if exists "Users can write own message feedback" on public.message_feedback;
create policy "Users can write own message feedback" on public.message_feedback
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "Users can update own message feedback" on public.message_feedback;
create policy "Users can update own message feedback" on public.message_feedback
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Users can delete own message feedback" on public.message_feedback;
create policy "Users can delete own message feedback" on public.message_feedback
for delete to authenticated using (user_id = auth.uid());

drop policy if exists "Users can read AI feedback" on public.ai_feedback;
create policy "Users can read AI feedback" on public.ai_feedback
for select to authenticated using (user_id = auth.uid());

drop policy if exists "Users can write own AI feedback" on public.ai_feedback;
create policy "Users can write own AI feedback" on public.ai_feedback
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "Users can update own AI feedback" on public.ai_feedback;
create policy "Users can update own AI feedback" on public.ai_feedback
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Users can delete own AI feedback" on public.ai_feedback;
create policy "Users can delete own AI feedback" on public.ai_feedback
for delete to authenticated using (user_id = auth.uid());
