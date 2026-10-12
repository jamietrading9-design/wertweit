alter table public.support_threads
    drop constraint if exists support_threads_status_check;

alter table public.support_threads
    add constraint support_threads_status_check
        check (status in ('open', 'in_progress', 'closed')),
    add column if not exists claimed_by uuid references auth.users (id) on delete set null,
    add column if not exists claimed_at timestamptz;

create index if not exists support_threads_claimed_by_updated_at_idx
    on public.support_threads (claimed_by, updated_at desc)
    where claimed_by is not null;
