alter table public.app_settings
    add column if not exists website_maintenance_enabled boolean not null default false,
    add column if not exists website_maintenance_message text not null default 'Die Website wird gerade gewartet. Bitte versuche es später erneut.',
    add column if not exists website_announcement_enabled boolean not null default false,
    add column if not exists website_announcement_title text not null default '',
    add column if not exists website_announcement_message text not null default '';

alter table public.app_settings
    drop constraint if exists app_settings_website_maintenance_message_length,
    add constraint app_settings_website_maintenance_message_length
        check (char_length(website_maintenance_message) between 1 and 500),
    drop constraint if exists app_settings_website_announcement_content_required,
    add constraint app_settings_website_announcement_content_required
        check (
            not website_announcement_enabled
            or (
                char_length(website_announcement_title) between 1 and 80
                and char_length(website_announcement_message) between 1 and 500
            )
        );
