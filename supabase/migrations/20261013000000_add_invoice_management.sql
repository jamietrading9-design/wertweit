create sequence if not exists public.invoice_number_seq
    as bigint
    start with 1
    increment by 1
    no minvalue
    no maxvalue
    cache 1;

revoke all on sequence public.invoice_number_seq from public, anon, authenticated;

create table if not exists public.invoice_settings (
    id smallint primary key default 1 check (id = 1),
    seller_name text not null default '',
    street text not null default '',
    postal_code text not null default '',
    city text not null default '',
    country text not null default 'Deutschland',
    email text not null default '',
    tax_identifier text not null default '',
    phone text not null default '',
    bank_account_holder text not null default '',
    bank_iban text not null default '',
    bank_bic text not null default '',
    invoice_prefix text not null default 'WW',
    invoice_logo_data_url text,
    updated_at timestamptz not null default now(),
    updated_by uuid references auth.users (id) on delete set null,
    constraint invoice_settings_prefix_format
        check (invoice_prefix ~ '^[A-Z0-9]{2,8}$'),
    constraint invoice_settings_bank_iban_length
        check (char_length(bank_iban) <= 34),
    constraint invoice_settings_bank_bic_length
        check (char_length(bank_bic) <= 11),
    constraint invoice_settings_logo_size
        check (invoice_logo_data_url is null or char_length(invoice_logo_data_url) <= 700000)
);

insert into public.invoice_settings (id)
values (1)
on conflict (id) do nothing;

create table if not exists public.invoice_customers (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    email text not null default '',
    street text not null,
    postal_code text not null,
    city text not null,
    country text not null default 'Deutschland',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint invoice_customers_name_length check (char_length(name) between 1 and 160),
    constraint invoice_customers_email_length check (char_length(email) <= 254),
    constraint invoice_customers_street_length check (char_length(street) between 1 and 200),
    constraint invoice_customers_postal_code_length check (char_length(postal_code) between 1 and 24),
    constraint invoice_customers_city_length check (char_length(city) between 1 and 120),
    constraint invoice_customers_country_length check (char_length(country) between 1 and 80)
);

create index if not exists invoice_customers_name_idx
    on public.invoice_customers (name);

create table if not exists public.invoice_products (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    unit_price_cents bigint not null check (unit_price_cents > 0 and unit_price_cents <= 100000000),
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint invoice_products_name_length check (char_length(name) between 1 and 200)
);

create index if not exists invoice_products_active_name_idx
    on public.invoice_products (lower(name))
    where active;

create table if not exists public.invoice_records (
    id uuid primary key default gen_random_uuid(),
    invoice_number text not null unique,
    customer_id uuid not null references public.invoice_customers (id) on delete restrict,
    invoice_date date not null,
    service_date date not null,
    due_date date not null,
    seller_snapshot jsonb not null,
    customer_snapshot jsonb not null,
    line_items jsonb not null,
    total_cents bigint not null check (total_cents > 0 and total_cents <= 10000000000),
    note text not null default '',
    paid_at timestamptz,
    created_at timestamptz not null default now(),
    created_by uuid references auth.users (id) on delete set null,
    constraint invoice_records_items_array check (
        jsonb_typeof(line_items) = 'array'
        and jsonb_array_length(line_items) between 1 and 50
    ),
    constraint invoice_records_seller_object check (jsonb_typeof(seller_snapshot) = 'object'),
    constraint invoice_records_customer_object check (jsonb_typeof(customer_snapshot) = 'object'),
    constraint invoice_records_note_length check (char_length(note) <= 2000),
    constraint invoice_records_due_date check (due_date >= invoice_date)
);

create index if not exists invoice_records_created_at_idx
    on public.invoice_records (created_at desc);
create index if not exists invoice_records_customer_id_idx
    on public.invoice_records (customer_id, invoice_date desc);

create or replace function public.admin_list_invoices(
    p_search text default '',
    p_status text default 'all',
    p_from date default null,
    p_to date default null,
    p_page integer default 1,
    p_per_page integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    result jsonb;
begin
    if p_page < 1 or p_per_page < 1 or p_per_page > 100 then
        raise exception 'Invalid invoice pagination';
    end if;
    if p_status not in ('all', 'open', 'paid') then
        raise exception 'Invalid invoice status';
    end if;

    with filtered as (
        select invoice.*
        from public.invoice_records as invoice
        where (
            coalesce(p_search, '') = ''
            or position(lower(p_search) in lower(invoice.invoice_number)) > 0
            or position(lower(p_search) in lower(invoice.customer_snapshot ->> 'name')) > 0
        )
          and (p_status = 'all'
               or (p_status = 'open' and invoice.paid_at is null)
               or (p_status = 'paid' and invoice.paid_at is not null))
          and (p_from is null or invoice.invoice_date >= p_from)
          and (p_to is null or invoice.invoice_date <= p_to)
    )
    select jsonb_build_object(
        'invoices',
        coalesce((
            select jsonb_agg(to_jsonb(invoice_page) order by invoice_page.created_at desc)
            from (
                select *
                from filtered
                order by created_at desc
                limit p_per_page
                offset (p_page - 1) * p_per_page
            ) as invoice_page
        ), '[]'::jsonb),
        'total',
        (select count(*) from filtered)
    )
    into result;

    return result;
end;
$$;

revoke all on function public.admin_list_invoices(text, text, date, date, integer, integer)
    from public, anon, authenticated;
grant execute on function public.admin_list_invoices(text, text, date, date, integer, integer)
    to service_role;

alter table public.invoice_settings enable row level security;
alter table public.invoice_customers enable row level security;
alter table public.invoice_products enable row level security;
alter table public.invoice_records enable row level security;

revoke all on public.invoice_settings from anon, authenticated;
revoke all on public.invoice_customers from anon, authenticated;
revoke all on public.invoice_products from anon, authenticated;
revoke all on public.invoice_records from anon, authenticated;

create or replace function public.admin_create_invoice(
    p_prefix text,
    p_customer_id uuid,
    p_invoice_date date,
    p_service_date date,
    p_due_date date,
    p_seller_snapshot jsonb,
    p_customer_snapshot jsonb,
    p_line_items jsonb,
    p_total_cents bigint,
    p_note text,
    p_created_by uuid
)
returns public.invoice_records
language plpgsql
security definer
set search_path = ''
as $$
declare
    invoice_number text;
    created_invoice public.invoice_records;
begin
    if p_prefix !~ '^[A-Z0-9]{2,8}$' then
        raise exception 'Invalid invoice number prefix';
    end if;

    invoice_number := p_prefix || '-' || to_char(p_invoice_date, 'YYYY') || '-' ||
        lpad(nextval('public.invoice_number_seq')::text, 6, '0');

    insert into public.invoice_records (
        invoice_number,
        customer_id,
        invoice_date,
        service_date,
        due_date,
        seller_snapshot,
        customer_snapshot,
        line_items,
        total_cents,
        note,
        created_by
    )
    values (
        invoice_number,
        p_customer_id,
        p_invoice_date,
        p_service_date,
        p_due_date,
        p_seller_snapshot,
        p_customer_snapshot,
        p_line_items,
        p_total_cents,
        p_note,
        p_created_by
    )
    returning * into created_invoice;

    return created_invoice;
end;
$$;

revoke all on function public.admin_create_invoice(
    text, uuid, date, date, date, jsonb, jsonb, jsonb, bigint, text, uuid
) from public, anon, authenticated;
grant execute on function public.admin_create_invoice(
    text, uuid, date, date, date, jsonb, jsonb, jsonb, bigint, text, uuid
) to service_role;
