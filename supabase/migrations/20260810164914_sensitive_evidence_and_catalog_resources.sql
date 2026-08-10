create table public.catalog_resources (
  id uuid not null,
  product_id uuid null,
  presentation_id uuid null,
  package_id uuid null,
  resource_kind text not null,
  source_reference text not null,
  alt_text text null,
  sort_order integer not null,
  is_primary boolean not null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_catalog_resources primary key (id),
  constraint fk_catalog_resources__products foreign key (product_id) references public.products (id) on delete restrict,
  constraint fk_catalog_resources__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint fk_catalog_resources__packages foreign key (package_id) references public.packages (id) on delete restrict,
  constraint ck_catalog_resources__single_owner check (
    (
      product_id is not null
      and presentation_id is null
      and package_id is null
    )
    or (
      product_id is null
      and presentation_id is not null
      and package_id is null
    )
    or (
      product_id is null
      and presentation_id is null
      and package_id is not null
    )
  ),
  constraint ck_catalog_resources__sort_order check (sort_order >= 0)
);

create index ix_catalog_resources__product_id
  on public.catalog_resources (product_id)
  where product_id is not null;

create index ix_catalog_resources__presentation_id
  on public.catalog_resources (presentation_id)
  where presentation_id is not null;

create index ix_catalog_resources__package_id
  on public.catalog_resources (package_id)
  where package_id is not null;

create table public.delivery_evidence_items (
  id uuid not null,
  delivery_id uuid not null,
  delivery_attempt_id uuid null,
  purpose text not null,
  evidence_kind text not null,
  retention_class text not null,
  dispute_context text null,
  exceptional_obligation_reference text null,
  content_reference text null,
  content_mime_type text null,
  is_sensitive boolean not null,
  retention_due_at timestamptz not null,
  review_at timestamptz null,
  deleted_at timestamptz null,
  deletion_reason text null,
  created_at timestamptz not null default now(),
  constraint pk_delivery_evidence_items primary key (id),
  constraint fk_delivery_evidence_items__deliveries foreign key (delivery_id) references public.deliveries (id) on delete restrict,
  constraint fk_delivery_evidence_items__delivery_attempts_same_delivery foreign key (delivery_id, delivery_attempt_id) references public.delivery_attempts (delivery_id, id) on delete restrict,
  constraint ck_delivery_evidence_items__retention_class check (
    retention_class in (
      'sensitive_no_dispute',
      'dispute_evidence',
      'exceptional_obligation'
    )
  ),
  constraint ck_delivery_evidence_items__dispute_context check (
    (
      retention_class = 'dispute_evidence'
      and dispute_context is not null
    )
    or (
      retention_class <> 'dispute_evidence'
      and dispute_context is null
    )
  ),
  constraint ck_delivery_evidence_items__exceptional_obligation check (
    (
      retention_class = 'exceptional_obligation'
      and exceptional_obligation_reference is not null
      and review_at is not null
    )
    or (
      retention_class <> 'exceptional_obligation'
      and exceptional_obligation_reference is null
      and review_at is null
    )
  ),
  constraint ck_delivery_evidence_items__deletion_metadata check (
    (
      deleted_at is null
      and deletion_reason is null
    )
    or (
      deleted_at is not null
      and deletion_reason is not null
    )
  )
);

create index ix_delivery_evidence_items__delivery_id
  on public.delivery_evidence_items (delivery_id);

create index ix_delivery_evidence_items__delivery_attempt_id
  on public.delivery_evidence_items (delivery_attempt_id)
  where delivery_attempt_id is not null;

create index ix_delivery_evidence_items__retention_due_at
  on public.delivery_evidence_items (retention_due_at);

create index ix_delivery_evidence_items__review_at
  on public.delivery_evidence_items (review_at)
  where review_at is not null;
