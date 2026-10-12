create table if not exists public.app_settings (
    id smallint primary key check (id = 1),
    maintenance_enabled boolean not null default false,
    maintenance_message text not null default 'Wertweit wird gerade gewartet. Bitte versuche es später erneut.',
    updated_at timestamptz not null default now(),
    updated_by uuid references auth.users (id) on delete set null,
    constraint app_settings_maintenance_message_length
        check (char_length(maintenance_message) between 1 and 500)
);

insert into public.app_settings (id)
values (1)
on conflict (id) do nothing;

alter table public.app_settings enable row level security;

revoke all on public.app_settings from anon, authenticated;
grant select on public.app_settings to anon, authenticated;

drop policy if exists "App status is publicly readable" on public.app_settings;
create policy "App status is publicly readable"
    on public.app_settings
    for select
    to anon, authenticated
    using (true);
