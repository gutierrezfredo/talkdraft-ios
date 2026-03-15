create table if not exists public.note_rewrite_jobs (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (
    status in ('queued', 'processing', 'completed', 'failed', 'completed_detached', 'canceled')
  ),
  source_content text not null,
  title_snapshot text,
  tone text,
  tone_label text,
  tone_emoji text,
  instructions text,
  note_updated_at_snapshot timestamptz not null,
  rewrite_id uuid references public.note_rewrites(id) on delete set null,
  error_message text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

create unique index if not exists note_rewrite_jobs_one_active_per_note
on public.note_rewrite_jobs (note_id)
where status in ('queued', 'processing');

alter table public.note_rewrite_jobs enable row level security;

create policy "Users can read their own rewrite jobs"
on public.note_rewrite_jobs
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can create rewrite jobs for their own notes"
on public.note_rewrite_jobs
for insert
to authenticated
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.notes
    where notes.id = note_id
      and notes.user_id = auth.uid()
  )
);
