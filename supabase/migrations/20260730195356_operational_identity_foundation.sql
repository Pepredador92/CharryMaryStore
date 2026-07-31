create table public.operational_people (
  id uuid not null,
  internal_reference text not null,
  display_name text not null,
  status text not null,
  started_at timestamptz null,
  ended_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_operational_people primary key (id),
  constraint uq_operational_people__internal_reference unique (internal_reference),
  constraint ck_operational_people__status
    check (status in ('active', 'suspended', 'ended'))
);

create table public.capabilities (
  id uuid not null,
  code text not null,
  name text not null,
  description text null,
  is_active boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_capabilities primary key (id),
  constraint uq_capabilities__code unique (code)
);
