create table if not exists public.app_user_access (
    user_id uuid primary key references auth.users (id) on delete cascade,
    blocked boolean not null default false,
    pro_until timestamptz,
    updated_at timestamptz not null default now(),
    updated_by uuid references auth.users (id) on delete set null
);

create table if not exists public.support_threads (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    subject text not null,
    status text not null default 'open' check (status in ('open', 'closed')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint support_threads_subject_length check (char_length(subject) between 1 and 120)
);

create table if not exists public.support_messages (
    id uuid primary key default gen_random_uuid(),
    thread_id uuid not null references public.support_threads (id) on delete cascade,
    sender_id uuid references auth.users (id) on delete set null,
    sender_is_admin boolean not null default false,
    body text not null,
    created_at timestamptz not null default now(),
    constraint support_messages_body_length check (char_length(body) between 1 and 5000)
);

create index if not exists support_threads_updated_at_idx
    on public.support_threads (updated_at desc);
create index if not exists support_threads_user_id_idx
    on public.support_threads (user_id, updated_at desc);
create index if not exists support_messages_thread_id_created_at_idx
    on public.support_messages (thread_id, created_at);

alter table public.app_user_access enable row level security;
alter table public.support_threads enable row level security;
alter table public.support_messages enable row level security;

revoke all on public.app_user_access from anon, authenticated;
revoke all on public.support_threads from anon, authenticated;
revoke all on public.support_messages from anon, authenticated;
