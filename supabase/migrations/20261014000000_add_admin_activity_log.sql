create table if not exists public.admin_activity_log (
    id bigint generated always as identity primary key,
    actor_id uuid references auth.users (id) on delete set null,
    actor_email text not null default '',
    action text not null,
    summary text not null,
    target_id uuid,
    target_label text not null default '',
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint admin_activity_log_action_length check (char_length(action) between 1 and 80),
    constraint admin_activity_log_summary_length check (char_length(summary) between 1 and 300),
    constraint admin_activity_log_target_label_length check (char_length(target_label) <= 254),
    constraint admin_activity_log_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create index if not exists admin_activity_log_created_at_idx
    on public.admin_activity_log (created_at desc);

alter table public.admin_activity_log enable row level security;
revoke all on public.admin_activity_log from public, anon, authenticated;

alter table public.app_settings
    add column if not exists announcement_enabled boolean not null default false,
    add column if not exists announcement_title text not null default '',
    add column if not exists announcement_message text not null default '';

alter table public.app_settings
    add constraint app_settings_announcement_title_length
        check (char_length(announcement_title) <= 80),
    add constraint app_settings_announcement_message_length
        check (char_length(announcement_message) <= 500),
    add constraint app_settings_announcement_content_required
        check (
            not announcement_enabled
            or (char_length(announcement_title) between 1 and 80
                and char_length(announcement_message) between 1 and 500)
        );
