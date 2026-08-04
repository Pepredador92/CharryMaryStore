create table public.operational_accounts (
  id uuid not null,
  operational_person_id uuid not null,
  auth_user_id uuid not null,
  status text not null,
  activated_at timestamptz null,
  revoked_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_operational_accounts primary key (id),
  constraint fk_operational_accounts__operational_people foreign key (operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_operational_accounts__auth_users foreign key (auth_user_id) references auth.users (id) on delete restrict,
  constraint uq_operational_accounts__auth_user_id unique (auth_user_id),
  constraint ck_operational_accounts__status
    check (status in ('invited', 'active', 'suspended', 'revoked'))
);

create unique index uq_operational_accounts__operational_person_id_current
  on public.operational_accounts (operational_person_id)
  where revoked_at is null;

create table public.operational_account_capabilities (
  id uuid not null,
  operational_account_id uuid not null,
  capability_id uuid not null,
  granted_by_person_id uuid not null,
  granted_at timestamptz not null,
  revoked_at timestamptz null,
  reason text null,
  created_at timestamptz not null default now(),
  constraint pk_operational_account_capabilities primary key (id),
  constraint fk_operational_account_capabilities__operational_accounts foreign key (operational_account_id) references public.operational_accounts (id) on delete restrict,
  constraint fk_operational_account_capabilities__capabilities foreign key (capability_id) references public.capabilities (id) on delete restrict,
  constraint fk_operational_account_capabilities__granted_by_operational_people foreign key (granted_by_person_id) references public.operational_people (id) on delete restrict
);

create unique index uq_operational_account_capabilities__operational_account_id_capability_id_active
  on public.operational_account_capabilities (operational_account_id, capability_id)
  where revoked_at is null;

create index ix_operational_account_capabilities__operational_account_id
  on public.operational_account_capabilities (operational_account_id);

create index ix_operational_account_capabilities__capability_id
  on public.operational_account_capabilities (capability_id);

create index ix_operational_account_capabilities__granted_by_person_id
  on public.operational_account_capabilities (granted_by_person_id);
