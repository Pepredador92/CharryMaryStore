create table public.carts (
  id uuid not null,
  personal_account_id uuid not null,
  status text not null,
  last_meaningful_activity_at timestamptz not null,
  expires_at timestamptz not null,
  converted_order_id uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_carts primary key (id),
  constraint fk_carts__personal_accounts foreign key (personal_account_id) references public.personal_accounts (id) on delete restrict,
  constraint ck_carts__expires_at check (expires_at = last_meaningful_activity_at + interval '60 days'),
  constraint ck_carts__status
    check (status in ('active', 'inactive', 'converted', 'expired')),
  constraint ck_carts__converted_order_id
    check (
      (status = 'converted' and converted_order_id is not null)
      or
      (status <> 'converted' and converted_order_id is null)
    )
);

create unique index uq_carts__personal_account_id_current
  on public.carts (personal_account_id)
  where status in ('active', 'inactive');

create index ix_carts__personal_account_id
  on public.carts (personal_account_id);

create index ix_carts__expires_at
  on public.carts (expires_at);

create table public.cart_lines (
  id uuid not null,
  cart_id uuid not null,
  line_kind text not null,
  presentation_id uuid null,
  package_id uuid null,
  quantity integer not null,
  catalog_updated_at_seen timestamptz null,
  validation_status text not null,
  last_validated_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_cart_lines primary key (id),
  constraint fk_cart_lines__carts foreign key (cart_id) references public.carts (id) on delete cascade,
  constraint fk_cart_lines__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint fk_cart_lines__packages foreign key (package_id) references public.packages (id) on delete restrict,
  constraint ck_cart_lines__single_target check (
    ((line_kind = 'presentation') and presentation_id is not null and package_id is null)
    or ((line_kind = 'package') and package_id is not null and presentation_id is null)
  ),
  constraint ck_cart_lines__quantity check (quantity > 0),
  constraint ck_cart_lines__validation_status
    check (validation_status in ('pending', 'valid', 'blocked', 'conflict'))
);

create unique index uq_cart_lines__cart_id_presentation_id
  on public.cart_lines (cart_id, presentation_id)
  where presentation_id is not null;

create index ix_cart_lines__cart_id
  on public.cart_lines (cart_id);

create index ix_cart_lines__presentation_id
  on public.cart_lines (presentation_id)
  where presentation_id is not null;

create index ix_cart_lines__package_id
  on public.cart_lines (package_id)
  where package_id is not null;
