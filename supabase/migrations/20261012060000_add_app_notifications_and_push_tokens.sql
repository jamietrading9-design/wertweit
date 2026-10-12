create table if not exists public.app_notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    title text not null check (length(title) between 1 and 150),
    body text not null check (length(body) between 1 and 500),
    kind text not null default 'admin_email',
    created_at timestamptz not null default now(),
    read_at timestamptz
);

create index if not exists app_notifications_user_created_idx
    on public.app_notifications (user_id, created_at desc);

alter table public.app_notifications enable row level security;
revoke all on public.app_notifications from anon, authenticated;

create table if not exists public.device_push_tokens (
    user_id uuid not null references auth.users (id) on delete cascade,
    device_token text not null check (device_token ~ '^[0-9a-f]{64}$'),
    enabled boolean not null default true,
    updated_at timestamptz not null default now(),
    primary key (user_id, device_token)
);

create index if not exists device_push_tokens_enabled_user_idx
    on public.device_push_tokens (user_id)
    where enabled;

alter table public.device_push_tokens enable row level security;
revoke all on public.device_push_tokens from anon, authenticated;
