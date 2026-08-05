create table public.orders (
  id uuid not null,
  order_number text not null,
  customer_id uuid not null,
  commercial_status text not null,
  currency_code char(3) not null,
  subtotal_amount_minor bigint not null,
  discount_amount_minor bigint not null,
  tax_amount_minor bigint not null,
  delivery_amount_minor bigint not null,
  total_amount_minor bigint not null,
  placed_at timestamptz not null,
  preparation_authorized_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_orders primary key (id),
  constraint uq_orders__order_number unique (order_number),
  constraint fk_orders__customers foreign key (customer_id) references public.customers (id) on delete restrict,
  constraint ck_orders__commercial_status check (commercial_status in ('pending_confirmation', 'confirmed', 'cancelled')),
  constraint ck_orders__subtotal_amount_minor check (subtotal_amount_minor >= 0),
  constraint ck_orders__discount_amount_minor check (discount_amount_minor >= 0),
  constraint ck_orders__tax_amount_minor check (tax_amount_minor >= 0),
  constraint ck_orders__delivery_amount_minor check (delivery_amount_minor >= 0),
  constraint ck_orders__total_amount_minor check (total_amount_minor >= 0),
  constraint ck_orders__discount_not_above_subtotal check (discount_amount_minor <= subtotal_amount_minor),
  constraint ck_orders__total_consistency check (
    total_amount_minor = subtotal_amount_minor - discount_amount_minor + tax_amount_minor + delivery_amount_minor
  ),
  constraint ck_orders__preparation_authorization_status check (
    preparation_authorized_at is null or commercial_status = 'confirmed'
  ),
  constraint ck_orders__preparation_authorized_at check (
    preparation_authorized_at is null or preparation_authorized_at >= placed_at
  )
);

create index ix_orders__customer_id
  on public.orders (customer_id);

alter table public.carts
  add constraint fk_carts__orders
  foreign key (converted_order_id)
  references public.orders (id)
  on delete restrict;

create index ix_carts__converted_order_id
  on public.carts (converted_order_id)
  where converted_order_id is not null;

create table public.order_destinations (
  id uuid not null,
  order_id uuid not null,
  version_number integer not null,
  is_current boolean not null,
  recipient_name text not null,
  reception_kind text null,
  contact_phone text null,
  contact_email text null,
  line_1 text not null,
  line_2 text null,
  neighborhood text null,
  city text not null,
  region text not null,
  postal_code text not null,
  country_code char(2) not null,
  delivery_instructions text null,
  authorized_at timestamptz not null,
  replaced_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint pk_order_destinations primary key (id),
  constraint fk_order_destinations__orders foreign key (order_id) references public.orders (id) on delete restrict,
  constraint uq_order_destinations__order_id_version_number unique (order_id, version_number),
  constraint ck_order_destinations__version_number check (version_number > 0),
  constraint ck_order_destinations__current_replacement check (
    (is_current = true and replaced_at is null)
    or (is_current = false and replaced_at is not null)
  ),
  constraint ck_order_destinations__replacement_time check (replaced_at is null or replaced_at > authorized_at)
);

create unique index uq_order_destinations__order_id_current
  on public.order_destinations (order_id)
  where is_current = true;

create table public.order_items (
  id uuid not null,
  order_id uuid not null,
  line_number integer not null,
  item_kind text not null,
  presentation_id uuid null,
  package_id uuid null,
  quantity integer not null,
  historical_name text not null,
  historical_sku text null,
  unit_price_amount_minor bigint not null,
  subtotal_amount_minor bigint not null,
  discount_amount_minor bigint not null,
  tax_amount_minor bigint not null,
  total_amount_minor bigint not null,
  currency_code char(3) not null,
  created_at timestamptz not null default now(),
  constraint pk_order_items primary key (id),
  constraint fk_order_items__orders foreign key (order_id) references public.orders (id) on delete restrict,
  constraint fk_order_items__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint fk_order_items__packages foreign key (package_id) references public.packages (id) on delete restrict,
  constraint uq_order_items__order_id_line_number unique (order_id, line_number),
  constraint ck_order_items__line_number check (line_number > 0),
  constraint ck_order_items__single_target check (
    (item_kind = 'presentation' and presentation_id is not null and package_id is null)
    or (item_kind = 'package' and package_id is not null and presentation_id is null)
  ),
  constraint ck_order_items__historical_sku_for_presentation check (
    item_kind <> 'presentation' or historical_sku is not null
  ),
  constraint ck_order_items__quantity check (quantity > 0),
  constraint ck_order_items__unit_price_amount_minor check (unit_price_amount_minor >= 0),
  constraint ck_order_items__subtotal_amount_minor check (subtotal_amount_minor >= 0),
  constraint ck_order_items__discount_amount_minor check (discount_amount_minor >= 0),
  constraint ck_order_items__tax_amount_minor check (tax_amount_minor >= 0),
  constraint ck_order_items__total_amount_minor check (total_amount_minor >= 0),
  constraint ck_order_items__discount_not_above_subtotal check (discount_amount_minor <= subtotal_amount_minor),
  constraint ck_order_items__subtotal_consistency check (
    subtotal_amount_minor = unit_price_amount_minor * quantity
  ),
  constraint ck_order_items__total_consistency check (
    total_amount_minor = subtotal_amount_minor - discount_amount_minor + tax_amount_minor
  )
);

create index ix_order_items__presentation_id
  on public.order_items (presentation_id)
  where presentation_id is not null;

create index ix_order_items__package_id
  on public.order_items (package_id)
  where package_id is not null;

create table public.order_item_package_components (
  id uuid not null,
  order_item_id uuid not null,
  presentation_id uuid null,
  historical_product_name text not null,
  historical_presentation_label text null,
  historical_sku text not null,
  quantity_per_package integer not null,
  total_component_quantity integer not null,
  created_at timestamptz not null default now(),
  constraint pk_order_item_package_components primary key (id),
  constraint fk_order_item_package_components__order_items foreign key (order_item_id) references public.order_items (id) on delete restrict,
  constraint fk_order_item_package_components__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint uq_order_item_package_components__order_item_id_historical_sku unique (order_item_id, historical_sku),
  constraint ck_order_item_package_components__quantity_per_package check (quantity_per_package > 0),
  constraint ck_order_item_package_components__total_component_quantity check (total_component_quantity > 0)
);

create index ix_order_item_package_components__presentation_id
  on public.order_item_package_components (presentation_id)
  where presentation_id is not null;

create table public.order_actions (
  id uuid not null,
  order_id uuid not null,
  action_kind text not null,
  actor_operational_person_id uuid not null,
  operational_account_id uuid not null,
  capability_id uuid not null,
  cause text null,
  previous_values jsonb null,
  new_values jsonb null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint pk_order_actions primary key (id),
  constraint fk_order_actions__orders foreign key (order_id) references public.orders (id) on delete restrict,
  constraint fk_order_actions__operational_people foreign key (actor_operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_order_actions__operational_accounts foreign key (operational_account_id) references public.operational_accounts (id) on delete restrict,
  constraint fk_order_actions__capabilities foreign key (capability_id) references public.capabilities (id) on delete restrict,
  constraint ck_order_actions__action_kind check (action_kind = 'preparation_authorized')
);

create index ix_order_actions__order_id
  on public.order_actions (order_id);

create index ix_order_actions__actor_operational_person_id
  on public.order_actions (actor_operational_person_id);

create index ix_order_actions__operational_account_id
  on public.order_actions (operational_account_id);

create index ix_order_actions__capability_id
  on public.order_actions (capability_id);
