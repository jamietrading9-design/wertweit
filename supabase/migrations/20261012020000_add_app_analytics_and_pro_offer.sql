alter table public.app_settings
    add column if not exists pro_offer_title text not null default 'Mehr Überblick auf Reisen.',
    add column if not exists pro_offer_message text not null default 'Der Währungsrechner bleibt kostenlos. Pro bündelt die Reise- und Analysewerkzeuge.',
    add column if not exists pro_monthly_offer_message text not null default 'Flexible Nutzung, monatliche Abrechnung.',
    add column if not exists pro_yearly_offer_message text not null default 'Der Jahreszugang für deine Reiseplanung.';

alter table public.app_settings
    add constraint app_settings_pro_offer_title_length
        check (char_length(pro_offer_title) between 1 and 80),
    add constraint app_settings_pro_offer_message_length
        check (char_length(pro_offer_message) between 1 and 500),
    add constraint app_settings_pro_monthly_offer_message_length
        check (char_length(pro_monthly_offer_message) between 1 and 160),
    add constraint app_settings_pro_yearly_offer_message_length
        check (char_length(pro_yearly_offer_message) between 1 and 160);

create table if not exists public.app_open_events (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users (id) on delete cascade,
    opened_at timestamptz not null default now()
);

create index if not exists app_open_events_opened_at_idx
    on public.app_open_events (opened_at desc);
create index if not exists app_open_events_user_opened_at_idx
    on public.app_open_events (user_id, opened_at desc);

alter table public.app_open_events enable row level security;
revoke all on public.app_open_events from anon, authenticated;

create or replace function public.record_app_open(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_user_id is null then
        raise exception 'A user ID is required';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

    if exists (
        select 1
        from public.app_open_events
        where user_id = p_user_id
          and opened_at >= now() - interval '30 minutes'
    ) then
        return false;
    end if;

    insert into public.app_open_events (user_id) values (p_user_id);

    delete from public.app_open_events
    where opened_at < now() - interval '365 days';

    return true;
end;
$$;

revoke all on function public.record_app_open(uuid) from public, anon, authenticated;
grant execute on function public.record_app_open(uuid) to service_role;

create or replace function public.admin_dashboard_metrics()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'app_opens_365d', (
            select count(*)
            from public.app_open_events
            where opened_at >= now() - interval '365 days'
        ),
        'app_opens_today', (
            select count(*)
            from public.app_open_events
            where opened_at >= date_trunc('day', now())
        ),
        'app_opens_30d', (
            select count(*)
            from public.app_open_events
            where opened_at >= now() - interval '30 days'
        ),
        'active_users_30d', (
            select count(distinct user_id)
            from public.app_open_events
            where opened_at >= now() - interval '30 days'
        ),
        'active_admin_pro', (
            select count(*)
            from public.app_user_access
            where pro_until > now()
        ),
        'blocked_accounts', (
            select count(*)
            from public.app_user_access
            where blocked
        ),
        'open_support_tickets', (
            select count(*)
            from public.support_threads
            where status = 'open'
        )
    );
$$;

revoke all on function public.admin_dashboard_metrics() from public, anon, authenticated;
grant execute on function public.admin_dashboard_metrics() to service_role;
