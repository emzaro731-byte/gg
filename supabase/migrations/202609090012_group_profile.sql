-- GG Messenger: richer group metadata
alter table public.conversations
  add column if not exists description text,
  add column if not exists avatar_path text;

alter table public.conversations
  drop constraint if exists conversations_description_length;

alter table public.conversations
  add constraint conversations_description_length
  check (description is null or char_length(description) <= 500);
