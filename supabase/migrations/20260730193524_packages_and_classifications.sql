create table public.packages (
  id uuid not null,
  name text not null,
  description text null,
  current_price_amount_minor bigint not null,
  currency_code char(3) not null,
  is_active boolean not null,
  valid_from timestamptz null,
  valid_until timestamptz null,
  archived_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_packages primary key (id),
  constraint ck_packages__current_price_amount_minor check (current_price_amount_minor >= 0),
  constraint ck_packages__validity_window check (valid_until is null or valid_from is null or valid_until > valid_from)
);

create table public.package_components (
  id uuid not null,
  package_id uuid not null,
  presentation_id uuid not null,
  quantity integer not null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_package_components primary key (id),
  constraint fk_package_components__packages foreign key (package_id) references public.packages (id) on delete restrict,
  constraint fk_package_components__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint uq_package_components__package_id_presentation_id unique (package_id, presentation_id),
  constraint ck_package_components__quantity check (quantity > 0)
);

create index ix_package_components__presentation_id
  on public.package_components (presentation_id);

create table public.commercial_classifications (
  id uuid not null,
  name text not null,
  description text null,
  parent_id uuid null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_commercial_classifications primary key (id),
  constraint fk_commercial_classifications__parent foreign key (parent_id) references public.commercial_classifications (id) on delete restrict,
  constraint ck_commercial_classifications__parent_id check (parent_id is null or parent_id <> id)
);

create index ix_commercial_classifications__parent_id
  on public.commercial_classifications (parent_id);

create table public.catalog_classification_assignments (
  id uuid not null,
  classification_id uuid not null,
  product_id uuid null,
  package_id uuid null,
  created_at timestamptz not null default now(),
  constraint pk_catalog_classification_assignments primary key (id),
  constraint fk_catalog_classification_assignments__commercial_classifications foreign key (classification_id) references public.commercial_classifications (id) on delete restrict,
  constraint fk_catalog_classification_assignments__products foreign key (product_id) references public.products (id) on delete restrict,
  constraint fk_catalog_classification_assignments__packages foreign key (package_id) references public.packages (id) on delete restrict,
  constraint ck_catalog_classification_assignments__single_target check (
    (product_id is not null and package_id is null)
    or (product_id is null and package_id is not null)
  )
);

create unique index uq_catalog_classification_assignments__classification_id_product_id
  on public.catalog_classification_assignments (classification_id, product_id)
  where product_id is not null;

create unique index uq_catalog_classification_assignments__classification_id_package_id
  on public.catalog_classification_assignments (classification_id, package_id)
  where package_id is not null;

create index ix_catalog_classification_assignments__product_id
  on public.catalog_classification_assignments (product_id)
  where product_id is not null;

create index ix_catalog_classification_assignments__package_id
  on public.catalog_classification_assignments (package_id)
  where package_id is not null;
