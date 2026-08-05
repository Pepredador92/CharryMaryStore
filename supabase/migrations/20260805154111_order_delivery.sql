alter table public.orders
  add column delivery_authorized_at timestamptz null,
  add constraint ck_orders__delivery_authorization_status check (
    delivery_authorized_at is null or commercial_status = 'confirmed'
  ),
  add constraint ck_orders__delivery_authorized_at check (
    delivery_authorized_at is null or delivery_authorized_at >= placed_at
  );

alter table public.order_actions
  drop constraint ck_order_actions__action_kind;

alter table public.order_actions
  add constraint ck_order_actions__action_kind check (
    action_kind in ('preparation_authorized', 'delivery_authorized')
  );

create table public.logistics_providers (
  id uuid not null,
  name text not null,
  external_reference text null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_logistics_providers primary key (id)
);

create table public.deliveries (
  id uuid not null,
  order_id uuid not null,
  status text not null,
  final_result text null,
  recognized_at timestamptz not null,
  custody_accepted_at timestamptz null,
  departed_at timestamptz null,
  completed_at timestamptz null,
  reopened_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_deliveries primary key (id),
  constraint fk_deliveries__orders foreign key (order_id) references public.orders (id) on delete restrict,
  constraint uq_deliveries__order_id unique (order_id),
  constraint ck_deliveries__status check (status in ('pending', 'in_custody', 'in_transit', 'blocked', 'completed', 'reopened')),
  constraint ck_deliveries__final_result check (
    final_result is null
    or final_result in ('delivered', 'ended_undelivered', 'cancelled_logistically', 'returned_to_origin', 'superseded')
  ),
  constraint ck_deliveries__completed_state check (
    (status = 'completed' and final_result is not null and completed_at is not null)
    or (status <> 'completed' and final_result is null and completed_at is null)
  ),
  constraint ck_deliveries__reopened_state check (
    status <> 'reopened' or reopened_at is not null
  )
);

create table public.delivery_assignments (
  id uuid not null,
  delivery_id uuid not null,
  operational_person_id uuid null,
  logistics_provider_id uuid null,
  external_person_reference text null,
  assignment_kind text not null,
  started_at timestamptz not null,
  ended_at timestamptz null,
  change_reason text null,
  created_at timestamptz not null default now(),
  constraint pk_delivery_assignments primary key (id),
  constraint fk_delivery_assignments__deliveries foreign key (delivery_id) references public.deliveries (id) on delete restrict,
  constraint fk_delivery_assignments__operational_people foreign key (operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_delivery_assignments__logistics_providers foreign key (logistics_provider_id) references public.logistics_providers (id) on delete restrict,
  constraint ck_delivery_assignments__single_assignee check (
    (operational_person_id is not null and logistics_provider_id is null)
    or (operational_person_id is null and logistics_provider_id is not null)
  ),
  constraint ck_delivery_assignments__external_person_reference check (
    external_person_reference is null or logistics_provider_id is not null
  ),
  constraint ck_delivery_assignments__time_range check (
    ended_at is null or ended_at >= started_at
  )
);

create table public.delivery_custody_events (
  id uuid not null,
  delivery_id uuid not null,
  event_kind text not null,
  from_party_kind text not null,
  from_operational_person_id uuid null,
  from_provider_id uuid null,
  to_party_kind text not null,
  to_operational_person_id uuid null,
  to_provider_id uuid null,
  external_party_reference text null,
  cause text null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint pk_delivery_custody_events primary key (id),
  constraint fk_delivery_custody_events__deliveries foreign key (delivery_id) references public.deliveries (id) on delete restrict,
  constraint fk_delivery_custody_events__from_operational_people foreign key (from_operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_delivery_custody_events__from_logistics_providers foreign key (from_provider_id) references public.logistics_providers (id) on delete restrict,
  constraint fk_delivery_custody_events__to_operational_people foreign key (to_operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_delivery_custody_events__to_logistics_providers foreign key (to_provider_id) references public.logistics_providers (id) on delete restrict,
  constraint ck_delivery_custody_events__event_kind check (event_kind in ('accepted', 'transferred', 'returned', 'released')),
  constraint ck_delivery_custody_events__from_party check (
    (from_party_kind = 'cherry_mary' and from_operational_person_id is null and from_provider_id is null)
    or (from_party_kind = 'operational_person' and from_operational_person_id is not null and from_provider_id is null)
    or (from_party_kind = 'logistics_provider' and from_operational_person_id is null and from_provider_id is not null)
    or (from_party_kind = 'external_party' and from_operational_person_id is null and from_provider_id is null)
  ),
  constraint ck_delivery_custody_events__to_party check (
    (to_party_kind = 'cherry_mary' and to_operational_person_id is null and to_provider_id is null)
    or (to_party_kind = 'operational_person' and to_operational_person_id is not null and to_provider_id is null)
    or (to_party_kind = 'logistics_provider' and to_operational_person_id is null and to_provider_id is not null)
    or (to_party_kind = 'external_party' and to_operational_person_id is null and to_provider_id is null)
  ),
  constraint ck_delivery_custody_events__external_party_reference check (
    (from_party_kind <> 'external_party' and to_party_kind <> 'external_party')
    or external_party_reference is not null
  )
);

create table public.delivery_attempts (
  id uuid not null,
  delivery_id uuid not null,
  attempt_number integer not null,
  result text not null,
  failure_cause text null,
  operational_person_id uuid null,
  logistics_provider_id uuid null,
  started_at timestamptz not null,
  completed_at timestamptz not null,
  destination_line_1 text not null,
  destination_line_2 text null,
  destination_city text not null,
  destination_region text not null,
  destination_postal_code text not null,
  destination_country_code char(2) not null,
  recipient_name_used text null,
  receipt_confirmation text null,
  event_source text not null,
  created_at timestamptz not null default now(),
  constraint pk_delivery_attempts primary key (id),
  constraint fk_delivery_attempts__deliveries foreign key (delivery_id) references public.deliveries (id) on delete restrict,
  constraint fk_delivery_attempts__operational_people foreign key (operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_delivery_attempts__logistics_providers foreign key (logistics_provider_id) references public.logistics_providers (id) on delete restrict,
  constraint uq_delivery_attempts__delivery_id_attempt_number unique (delivery_id, attempt_number),
  constraint uq_delivery_attempts__delivery_id_id unique (delivery_id, id),
  constraint ck_delivery_attempts__attempt_number check (attempt_number > 0),
  constraint ck_delivery_attempts__result check (result in ('delivered', 'failed', 'rejected', 'inaccessible', 'cancelled')),
  constraint ck_delivery_attempts__single_responsible_party check (
    (operational_person_id is not null and logistics_provider_id is null)
    or (operational_person_id is null and logistics_provider_id is not null)
  ),
  constraint ck_delivery_attempts__completion_time check (completed_at >= started_at),
  constraint ck_delivery_attempts__result_details check (
    (result = 'delivered' and receipt_confirmation is not null and failure_cause is null)
    or (result <> 'delivered' and receipt_confirmation is null and failure_cause is not null)
  )
);

create table public.delivery_actions (
  id uuid not null,
  delivery_id uuid not null,
  attempt_id uuid null,
  action_kind text not null,
  actor_operational_person_id uuid not null,
  operational_account_id uuid not null,
  capability_id uuid not null,
  cause text not null,
  previous_values jsonb null,
  new_values jsonb null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint pk_delivery_actions primary key (id),
  constraint fk_delivery_actions__deliveries foreign key (delivery_id) references public.deliveries (id) on delete restrict,
  constraint fk_delivery_actions__delivery_attempts_same_delivery foreign key (delivery_id, attempt_id) references public.delivery_attempts (delivery_id, id) on delete restrict,
  constraint fk_delivery_actions__operational_people foreign key (actor_operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_delivery_actions__operational_accounts foreign key (operational_account_id) references public.operational_accounts (id) on delete restrict,
  constraint fk_delivery_actions__capabilities foreign key (capability_id) references public.capabilities (id) on delete restrict,
  constraint ck_delivery_actions__action_kind check (
    action_kind in ('blocked', 'rescheduled', 'corrected', 'disposition_authorized', 'completed', 'reopened', 'assignment_changed')
  )
);

create index ix_delivery_assignments__delivery_id
  on public.delivery_assignments (delivery_id);

create index ix_delivery_assignments__operational_person_id
  on public.delivery_assignments (operational_person_id)
  where operational_person_id is not null;

create index ix_delivery_assignments__logistics_provider_id
  on public.delivery_assignments (logistics_provider_id)
  where logistics_provider_id is not null;

create index ix_delivery_custody_events__delivery_id
  on public.delivery_custody_events (delivery_id);

create index ix_delivery_custody_events__from_operational_person_id
  on public.delivery_custody_events (from_operational_person_id)
  where from_operational_person_id is not null;

create index ix_delivery_custody_events__from_provider_id
  on public.delivery_custody_events (from_provider_id)
  where from_provider_id is not null;

create index ix_delivery_custody_events__to_operational_person_id
  on public.delivery_custody_events (to_operational_person_id)
  where to_operational_person_id is not null;

create index ix_delivery_custody_events__to_provider_id
  on public.delivery_custody_events (to_provider_id)
  where to_provider_id is not null;

create index ix_delivery_custody_events__occurred_at
  on public.delivery_custody_events (occurred_at);

create index ix_delivery_attempts__operational_person_id
  on public.delivery_attempts (operational_person_id)
  where operational_person_id is not null;

create index ix_delivery_attempts__logistics_provider_id
  on public.delivery_attempts (logistics_provider_id)
  where logistics_provider_id is not null;

create index ix_delivery_actions__delivery_id
  on public.delivery_actions (delivery_id);

create index ix_delivery_actions__attempt_id
  on public.delivery_actions (attempt_id)
  where attempt_id is not null;

create index ix_delivery_actions__actor_operational_person_id
  on public.delivery_actions (actor_operational_person_id);

create index ix_delivery_actions__operational_account_id
  on public.delivery_actions (operational_account_id);

create index ix_delivery_actions__capability_id
  on public.delivery_actions (capability_id);

create index ix_delivery_actions__occurred_at
  on public.delivery_actions (occurred_at);
