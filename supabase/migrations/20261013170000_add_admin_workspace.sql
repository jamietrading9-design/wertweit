alter table public.invoice_customers
    add column if not exists pro_customer boolean not null default false;

create table if not exists public.private_sale_customers (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    email text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint private_sale_customers_name_length check (char_length(name) between 1 and 160),
    constraint private_sale_customers_email_length check (char_length(email) <= 254)
);

create index if not exists private_sale_customers_name_idx
    on public.private_sale_customers (name);

create table if not exists public.private_sale_settings (
    id smallint primary key default 1 check (id = 1),
    seller_name text not null default '',
    seller_email text not null default '',
    updated_at timestamptz not null default now(),
    updated_by uuid references auth.users (id) on delete set null,
    constraint private_sale_settings_name_length check (char_length(seller_name) <= 160),
    constraint private_sale_settings_email_length check (char_length(seller_email) <= 254)
);

insert into public.private_sale_settings (id)
values (1)
on conflict (id) do nothing;

create sequence if not exists public.private_sale_receipt_number_seq
    as bigint
    start with 1
    increment by 1
    no minvalue
    no maxvalue
    cache 1;

revoke all on sequence public.private_sale_receipt_number_seq from public, anon, authenticated;

create table if not exists public.private_sale_receipts (
    id uuid primary key default gen_random_uuid(),
    receipt_number text not null unique,
    customer_id uuid not null references public.private_sale_customers (id) on delete restrict,
    receipt_date date not null,
    seller_snapshot jsonb not null,
    customer_snapshot jsonb not null,
    line_items jsonb not null,
    total_cents bigint not null check (total_cents > 0 and total_cents <= 10000000000),
    note text not null default '',
    created_at timestamptz not null default now(),
    created_by uuid references auth.users (id) on delete set null,
    constraint private_sale_receipts_items_array check (
        jsonb_typeof(line_items) = 'array'
        and jsonb_array_length(line_items) between 1 and 50
    ),
    constraint private_sale_receipts_seller_object check (jsonb_typeof(seller_snapshot) = 'object'),
    constraint private_sale_receipts_customer_object check (jsonb_typeof(customer_snapshot) = 'object'),
    constraint private_sale_receipts_note_length check (char_length(note) <= 2000)
);

create index if not exists private_sale_receipts_created_at_idx
    on public.private_sale_receipts (created_at desc);
create index if not exists private_sale_receipts_customer_id_idx
    on public.private_sale_receipts (customer_id, receipt_date desc);

alter table public.private_sale_customers enable row level security;
alter table public.private_sale_receipts enable row level security;
alter table public.private_sale_settings enable row level security;
revoke all on public.private_sale_customers from anon, authenticated;
revoke all on public.private_sale_receipts from anon, authenticated;
revoke all on public.private_sale_settings from anon, authenticated;

create or replace function public.admin_create_private_sale_receipt(
    p_customer_id uuid,
    p_receipt_date date,
    p_seller_snapshot jsonb,
    p_customer_snapshot jsonb,
    p_line_items jsonb,
    p_total_cents bigint,
    p_note text,
    p_created_by uuid
)
returns public.private_sale_receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
    receipt_number text;
    created_receipt public.private_sale_receipts;
begin
    receipt_number := 'PR-' || to_char(p_receipt_date, 'YYYY') || '-' ||
        lpad(nextval('public.private_sale_receipt_number_seq')::text, 6, '0');

    insert into public.private_sale_receipts (
        receipt_number,
        customer_id,
        receipt_date,
        seller_snapshot,
        customer_snapshot,
        line_items,
        total_cents,
        note,
        created_by
    )
    values (
        receipt_number,
        p_customer_id,
        p_receipt_date,
        p_seller_snapshot,
        p_customer_snapshot,
        p_line_items,
        p_total_cents,
        p_note,
        p_created_by
    )
    returning * into created_receipt;

    return created_receipt;
end;
$$;

revoke all on function public.admin_create_private_sale_receipt(
    uuid, date, jsonb, jsonb, jsonb, bigint, text, uuid
) from public, anon, authenticated;
grant execute on function public.admin_create_private_sale_receipt(
    uuid, date, jsonb, jsonb, jsonb, bigint, text, uuid
) to service_role;
