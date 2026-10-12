create table if not exists public.email_update_preferences (
    user_id uuid primary key references auth.users (id) on delete cascade,
    subscribed boolean not null default false,
    subscribed_at timestamptz,
    updated_at timestamptz not null default now(),
    constraint email_update_consent_timestamp
        check (subscribed = (subscribed_at is not null))
);

create index if not exists email_update_preferences_subscribed_idx
    on public.email_update_preferences (user_id)
    where subscribed;

alter table public.email_update_preferences enable row level security;
revoke all on public.email_update_preferences from anon, authenticated;
