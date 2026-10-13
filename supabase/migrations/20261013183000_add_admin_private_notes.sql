create table if not exists public.admin_private_notes (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users (id) on delete cascade,
    thread_id uuid references public.support_threads (id) on delete cascade,
    label text not null default 'Interne Notiz',
    body text not null,
    created_by uuid references auth.users (id) on delete set null,
    updated_by uuid references auth.users (id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint admin_private_notes_single_target check (
        (user_id is not null and thread_id is null)
        or (user_id is null and thread_id is not null)
    ),
    constraint admin_private_notes_label_length check (char_length(label) between 1 and 80),
    constraint admin_private_notes_body_length check (char_length(body) between 1 and 4000)
);

create index if not exists admin_private_notes_user_created_idx
    on public.admin_private_notes (user_id, created_at desc)
    where user_id is not null;
create index if not exists admin_private_notes_thread_created_idx
    on public.admin_private_notes (thread_id, created_at desc)
    where thread_id is not null;

alter table public.admin_private_notes enable row level security;
revoke all on public.admin_private_notes from anon, authenticated;
