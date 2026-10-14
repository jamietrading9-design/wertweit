create table if not exists public.demo_pro_entitlements (
    user_id uuid primary key references auth.users (id) on delete cascade,
    activated_at timestamptz not null default now(),
    expires_at timestamptz not null,
    confirmation_sent_at timestamptz,
    confirmation_error text,
    constraint demo_pro_entitlements_expiry_after_activation
        check (expires_at > activated_at),
    constraint demo_pro_entitlements_confirmation_error_length
        check (confirmation_error is null or char_length(confirmation_error) <= 500)
);

create index if not exists demo_pro_entitlements_expires_at_idx
    on public.demo_pro_entitlements (expires_at);

alter table public.demo_pro_entitlements enable row level security;
revoke all on public.demo_pro_entitlements from public, anon, authenticated;
