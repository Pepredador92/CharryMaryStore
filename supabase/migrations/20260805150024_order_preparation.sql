create table public.preparations (
  id uuid not null,
  order_id uuid not null,
  status text not null,
  current_responsible_person_id uuid null,
  started_at timestamptz null,
  blocked_at timestamptz null,
  completed_at timestamptz null,
  terminated_at timestamptz null,
  reopened_at timestamptz null,
  current_block_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_preparations primary key (id),
  constraint fk_preparations__orders foreign key (order_id) references public.orders (id) on delete restrict,
  constraint fk_preparations__current_responsible_operational_people foreign key (current_responsible_person_id) references public.operational_people (id) on delete restrict,
  constraint uq_preparations__order_id unique (order_id),
  constraint ck_preparations__status check (status in ('pending', 'in_progress', 'blocked', 'completed', 'ended_incomplete', 'reopened')),
  constraint ck_preparations__blocked_state check (
    (status = 'blocked' and blocked_at is not null and current_block_reason is not null)
    or (status <> 'blocked' and blocked_at is null and current_block_reason is null)
  ),
  constraint ck_preparations__completed_state check (
    (status = 'completed' and completed_at is not null)
    or (status <> 'completed' and completed_at is null)
  ),
  constraint ck_preparations__ended_incomplete_state check (
    (status = 'ended_incomplete' and terminated_at is not null)
    or (status <> 'ended_incomplete' and terminated_at is null)
  ),
  constraint ck_preparations__reopened_state check (
    status <> 'reopened' or reopened_at is not null
  ),
  constraint ck_preparations__started_state check (
    status not in ('in_progress', 'completed', 'reopened') or started_at is not null
  )
);

create index ix_preparations__current_responsible_person_id
  on public.preparations (current_responsible_person_id)
  where current_responsible_person_id is not null;

create table public.preparation_actions (
  id uuid not null,
  preparation_id uuid not null,
  order_item_id uuid null,
  action_kind text not null,
  actor_operational_person_id uuid not null,
  operational_account_id uuid not null,
  capability_id uuid not null,
  result text null,
  cause text null,
  details jsonb null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint pk_preparation_actions primary key (id),
  constraint fk_preparation_actions__preparations foreign key (preparation_id) references public.preparations (id) on delete restrict,
  constraint fk_preparation_actions__order_items foreign key (order_item_id) references public.order_items (id) on delete restrict,
  constraint fk_preparation_actions__operational_people foreign key (actor_operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_preparation_actions__operational_accounts foreign key (operational_account_id) references public.operational_accounts (id) on delete restrict,
  constraint fk_preparation_actions__capabilities foreign key (capability_id) references public.capabilities (id) on delete restrict
);

create index ix_preparation_actions__preparation_id
  on public.preparation_actions (preparation_id);

create index ix_preparation_actions__order_item_id
  on public.preparation_actions (order_item_id)
  where order_item_id is not null;

create index ix_preparation_actions__actor_operational_person_id
  on public.preparation_actions (actor_operational_person_id);

create index ix_preparation_actions__operational_account_id
  on public.preparation_actions (operational_account_id);

create index ix_preparation_actions__capability_id
  on public.preparation_actions (capability_id);

create index ix_preparation_actions__occurred_at
  on public.preparation_actions (occurred_at);

create table public.preparation_item_verifications (
  id uuid not null,
  preparation_id uuid not null,
  order_item_id uuid not null,
  verification_status text not null,
  verified_quantity integer not null,
  last_action_id uuid null,
  verified_by_person_id uuid null,
  verified_at timestamptz null,
  invalidated_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_preparation_item_verifications primary key (id),
  constraint fk_preparation_item_verifications__preparations foreign key (preparation_id) references public.preparations (id) on delete restrict,
  constraint fk_preparation_item_verifications__order_items foreign key (order_item_id) references public.order_items (id) on delete restrict,
  constraint fk_preparation_item_verifications__last_preparation_action foreign key (last_action_id) references public.preparation_actions (id) on delete restrict,
  constraint fk_preparation_item_verifications__verified_by_operational_people foreign key (verified_by_person_id) references public.operational_people (id) on delete restrict,
  constraint uq_preparation_item_verifications__preparation_id_order_item_id unique (preparation_id, order_item_id),
  constraint ck_preparation_item_verifications__verification_status check (
    verification_status in ('pending', 'verified', 'invalidated', 'blocked')
  ),
  constraint ck_preparation_item_verifications__verified_quantity check (verified_quantity >= 0),
  constraint ck_preparation_item_verifications__verified_state check (
    verification_status <> 'verified'
    or (
      verified_quantity > 0
      and verified_by_person_id is not null
      and verified_at is not null
      and invalidated_at is null
    )
  ),
  constraint ck_preparation_item_verifications__invalidated_state check (
    (
      verification_status = 'invalidated'
      and verified_quantity > 0
      and verified_by_person_id is not null
      and verified_at is not null
      and invalidated_at is not null
      and invalidated_at > verified_at
    )
    or (
      verification_status <> 'invalidated'
      and invalidated_at is null
    )
  )
);

create index ix_preparation_item_verifications__order_item_id
  on public.preparation_item_verifications (order_item_id);

create index ix_preparation_item_verifications__last_action_id
  on public.preparation_item_verifications (last_action_id)
  where last_action_id is not null;

create index ix_preparation_item_verifications__verified_by_person_id
  on public.preparation_item_verifications (verified_by_person_id)
  where verified_by_person_id is not null;
