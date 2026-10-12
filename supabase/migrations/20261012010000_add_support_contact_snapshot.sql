alter table public.support_threads
    add column if not exists user_email text not null default '';
