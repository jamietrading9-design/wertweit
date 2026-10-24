alter table public.app_settings
    add column if not exists announcement_starts_at timestamptz,
    add column if not exists announcement_ends_at timestamptz,
    add column if not exists website_announcement_starts_at timestamptz,
    add column if not exists website_announcement_ends_at timestamptz;

alter table public.app_settings
    drop constraint if exists app_settings_announcement_schedule_order,
    add constraint app_settings_announcement_schedule_order
        check (
            announcement_starts_at is null
            or announcement_ends_at is null
            or announcement_ends_at > announcement_starts_at
        ),
    drop constraint if exists app_settings_website_announcement_schedule_order,
    add constraint app_settings_website_announcement_schedule_order
        check (
            website_announcement_starts_at is null
            or website_announcement_ends_at is null
            or website_announcement_ends_at > website_announcement_starts_at
        );
