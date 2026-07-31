create table public.products (
  id uuid not null,
  name text not null,
  description text null,
  usage_instructions text null,
  warnings text null,
  is_active boolean not null default true,
  archived_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_products primary key (id)
);

create table public.sellable_presentations (
  id uuid not null,
  product_id uuid not null,
  sku text not null,
  variant_label text null,
  attributes jsonb null,
  current_price_amount_minor bigint not null,
  currency_code char(3) not null,
  is_active boolean not null,
  archived_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_sellable_presentations primary key (id),
  constraint fk_sellable_presentations__products foreign key (product_id) references public.products (id) on delete restrict,
  constraint uq_sellable_presentations__sku unique (sku),
  constraint ck_sellable_presentations__current_price_amount_minor check (current_price_amount_minor >= 0)
);

create index ix_sellable_presentations__product_id
  on public.sellable_presentations (product_id);

create table public.presentation_inventory (
  presentation_id uuid not null,
  on_hand_quantity bigint not null,
  updated_at timestamptz not null default now(),
  constraint pk_presentation_inventory primary key (presentation_id),
  constraint fk_presentation_inventory__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint ck_presentation_inventory__on_hand_quantity check (on_hand_quantity >= 0)
);
