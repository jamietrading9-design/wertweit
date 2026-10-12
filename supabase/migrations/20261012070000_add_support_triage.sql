alter table public.support_threads
    add column if not exists support_category text not null default 'other'
        check (support_category in ('account', 'payment', 'bug', 'feature', 'other')),
    add column if not exists support_priority text not null default 'green'
        check (support_priority in ('red', 'yellow', 'green'));

create index if not exists support_threads_priority_updated_idx
    on public.support_threads (support_priority, updated_at desc);
