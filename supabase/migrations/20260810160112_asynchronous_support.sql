create table public.support_requests (
  id uuid not null,
  requester_kind text not null,
  customer_id uuid null,
  personal_account_id uuid null,
  pseudonymous_reference text null,
  contact_email text null,
  contact_phone text null,
  subject text not null,
  purpose text not null,
  status text not null,
  product_id uuid null,
  presentation_id uuid null,
  package_id uuid null,
  order_id uuid null,
  preparation_id uuid null,
  delivery_id uuid null,
  opened_at timestamptz not null,
  closed_at timestamptz null,
  closure_reason text null,
  retention_class text not null,
  retention_due_at timestamptz null,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_support_requests primary key (id),
  constraint fk_support_requests__customers foreign key (customer_id) references public.customers (id) on delete restrict,
  constraint fk_support_requests__personal_accounts foreign key (personal_account_id) references public.personal_accounts (id) on delete restrict,
  constraint fk_support_requests__products foreign key (product_id) references public.products (id) on delete restrict,
  constraint fk_support_requests__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint fk_support_requests__packages foreign key (package_id) references public.packages (id) on delete restrict,
  constraint fk_support_requests__orders foreign key (order_id) references public.orders (id) on delete restrict,
  constraint fk_support_requests__preparations foreign key (preparation_id) references public.preparations (id) on delete restrict,
  constraint fk_support_requests__deliveries foreign key (delivery_id) references public.deliveries (id) on delete restrict,
  constraint ck_support_requests__requester_kind check (requester_kind in ('visitor', 'customer', 'account')),
  constraint ck_support_requests__requester_identity check (
    (requester_kind = 'visitor' and customer_id is null and personal_account_id is null)
    or (requester_kind = 'customer' and customer_id is not null and personal_account_id is null)
    or (requester_kind = 'account' and personal_account_id is not null and customer_id is null)
  ),
  constraint ck_support_requests__pseudonymous_reference check (
    pseudonymous_reference is null or requester_kind = 'visitor'
  ),
  constraint ck_support_requests__single_subject_reference check (
    (case when product_id is not null then 1 else 0 end)
    + (case when presentation_id is not null then 1 else 0 end)
    + (case when package_id is not null then 1 else 0 end)
    + (case when order_id is not null then 1 else 0 end)
    + (case when preparation_id is not null then 1 else 0 end)
    + (case when delivery_id is not null then 1 else 0 end)
    <= 1
  ),
  constraint ck_support_requests__status check (
    status in (
      'open',
      'in_attention',
      'resolved',
      'channelled',
      'closed'
    )
  ),
  constraint ck_support_requests__closure_state check (
    (
      status = 'closed'
      and closed_at is not null
      and closure_reason is not null
    )
    or (
      status <> 'closed'
      and closed_at is null
      and closure_reason is null
    )
  ),
  constraint ck_support_requests__closure_time check (
    closed_at is null or closed_at >= opened_at
  ),
  constraint ck_support_requests__retention_class check (retention_class in ('14_day', '90_day')),
  constraint ck_support_requests__retention_scope check (
    (
      order_id is null
      and preparation_id is null
      and delivery_id is null
      and retention_class = '14_day'
    )
    or (
      (
        order_id is not null
        or preparation_id is not null
        or delivery_id is not null
      )
      and retention_class = '90_day'
    )
  ),
  constraint ck_support_requests__retention_state check (
    (
      status in ('open', 'in_attention', 'resolved', 'channelled')
      and retention_due_at is null
    )
    or (
      status = 'closed'
      and retention_due_at is not null
    )
  ),
  constraint ck_support_requests__retention_due_at check (
    closed_at is null
    or (
      (retention_class = '14_day' and retention_due_at = closed_at + interval '14 days')
      or (retention_class = '90_day' and retention_due_at = closed_at + interval '90 days')
    )
  )
);

create index ix_support_requests__customer_id
  on public.support_requests (customer_id)
  where customer_id is not null;

create index ix_support_requests__personal_account_id
  on public.support_requests (personal_account_id)
  where personal_account_id is not null;

create index ix_support_requests__product_id
  on public.support_requests (product_id)
  where product_id is not null;

create index ix_support_requests__presentation_id
  on public.support_requests (presentation_id)
  where presentation_id is not null;

create index ix_support_requests__package_id
  on public.support_requests (package_id)
  where package_id is not null;

create index ix_support_requests__order_id
  on public.support_requests (order_id)
  where order_id is not null;

create index ix_support_requests__preparation_id
  on public.support_requests (preparation_id)
  where preparation_id is not null;

create index ix_support_requests__delivery_id
  on public.support_requests (delivery_id)
  where delivery_id is not null;

create index ix_support_requests__retention_due_at
  on public.support_requests (retention_due_at)
  where retention_due_at is not null;

create table public.support_messages (
  id uuid not null,
  support_request_id uuid not null,
  direction text not null,
  author_kind text not null,
  operational_person_id uuid null,
  operational_account_id uuid null,
  capability_id uuid null,
  body text not null,
  channel text not null,
  is_sensitive boolean not null,
  sent_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint pk_support_messages primary key (id),
  constraint fk_support_messages__support_requests foreign key (support_request_id) references public.support_requests (id) on delete restrict,
  constraint fk_support_messages__operational_people foreign key (operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_support_messages__operational_accounts foreign key (operational_account_id) references public.operational_accounts (id) on delete restrict,
  constraint fk_support_messages__capabilities foreign key (capability_id) references public.capabilities (id) on delete restrict,
  constraint ck_support_messages__direction check (direction in ('incoming', 'outgoing')),
  constraint ck_support_messages__author_kind check (author_kind in ('visitor', 'customer', 'operational_person', 'system_notification')),
  constraint ck_support_messages__operational_attribution check (
    (
      author_kind = 'operational_person'
      and operational_person_id is not null
      and (
        (operational_account_id is null and capability_id is null)
        or (operational_account_id is not null and capability_id is not null)
      )
    )
    or (
      author_kind <> 'operational_person'
      and operational_person_id is null
      and operational_account_id is null
      and capability_id is null
    )
  ),
  constraint ck_support_messages__channel check (channel in ('internal', 'email_notification')),
  constraint ck_support_messages__email_direction check (
    channel <> 'email_notification' or direction = 'outgoing'
  )
);

create index ix_support_messages__support_request_id
  on public.support_messages (support_request_id);

create index ix_support_messages__operational_person_id
  on public.support_messages (operational_person_id)
  where operational_person_id is not null;

create index ix_support_messages__operational_account_id
  on public.support_messages (operational_account_id)
  where operational_account_id is not null;

create index ix_support_messages__capability_id
  on public.support_messages (capability_id)
  where capability_id is not null;
