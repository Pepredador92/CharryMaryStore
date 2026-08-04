create table public.customers (
  id uuid not null,
  preferred_name text null,
  contact_email text null,
  contact_phone text null,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_customers primary key (id),
  constraint ck_customers__status
    check (status in ('active', 'inactive'))
);

create table public.personal_accounts (
  id uuid not null,
  customer_id uuid not null,
  auth_user_id uuid not null,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_personal_accounts primary key (id),
  constraint fk_personal_accounts__customers foreign key (customer_id) references public.customers (id) on delete restrict,
  constraint fk_personal_accounts__auth_users foreign key (auth_user_id) references auth.users (id) on delete restrict,
  constraint uq_personal_accounts__customer_id unique (customer_id),
  constraint uq_personal_accounts__auth_user_id unique (auth_user_id),
  constraint ck_personal_accounts__status
    check (status in ('active', 'suspended', 'revoked'))
);

create table public.customer_addresses (
  id uuid not null,
  customer_id uuid not null,
  label text null,
  recipient_name text null,
  contact_phone text null,
  line_1 text not null,
  line_2 text null,
  neighborhood text null,
  city text not null,
  region text not null,
  postal_code text not null,
  country_code char(2) not null,
  delivery_instructions text null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_customer_addresses primary key (id),
  constraint fk_customer_addresses__customers foreign key (customer_id) references public.customers (id) on delete restrict
);

create index ix_customer_addresses__customer_id
  on public.customer_addresses (customer_id);
