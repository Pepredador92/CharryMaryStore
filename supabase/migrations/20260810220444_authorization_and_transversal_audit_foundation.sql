create schema private;

revoke all on schema private from PUBLIC;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
grant usage on schema private to authenticated;

create function private.current_operational_account_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select public.operational_accounts.id
  from public.operational_accounts
  join public.operational_people
    on public.operational_people.id = public.operational_accounts.operational_person_id
  where auth.uid() is not null
    and public.operational_accounts.auth_user_id = auth.uid()
    and public.operational_accounts.status = 'active'
    and public.operational_accounts.activated_at is not null
    and public.operational_accounts.revoked_at is null
    and public.operational_people.status = 'active'
    and public.operational_people.ended_at is null
  limit 1
$$;

revoke all on function private.current_operational_account_id() from PUBLIC;
revoke all on function private.current_operational_account_id() from anon;
revoke all on function private.current_operational_account_id() from authenticated;
grant execute on function private.current_operational_account_id() to authenticated;

create function private.current_operational_person_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select public.operational_people.id
  from public.operational_accounts
  join public.operational_people
    on public.operational_people.id = public.operational_accounts.operational_person_id
  where auth.uid() is not null
    and public.operational_accounts.auth_user_id = auth.uid()
    and public.operational_accounts.status = 'active'
    and public.operational_accounts.activated_at is not null
    and public.operational_accounts.revoked_at is null
    and public.operational_people.status = 'active'
    and public.operational_people.ended_at is null
  limit 1
$$;

revoke all on function private.current_operational_person_id() from PUBLIC;
revoke all on function private.current_operational_person_id() from anon;
revoke all on function private.current_operational_person_id() from authenticated;
grant execute on function private.current_operational_person_id() to authenticated;

create function private.has_capability(p_capability_code text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.operational_accounts
    join public.operational_people
      on public.operational_people.id = public.operational_accounts.operational_person_id
    join public.operational_account_capabilities
      on public.operational_account_capabilities.operational_account_id = public.operational_accounts.id
    join public.capabilities
      on public.capabilities.id = public.operational_account_capabilities.capability_id
    where auth.uid() is not null
      and public.operational_accounts.auth_user_id = auth.uid()
      and public.operational_accounts.status = 'active'
      and public.operational_accounts.activated_at is not null
      and public.operational_accounts.revoked_at is null
      and public.operational_people.status = 'active'
      and public.operational_people.ended_at is null
      and public.capabilities.code = p_capability_code
      and public.capabilities.is_active = true
      and public.operational_account_capabilities.revoked_at is null
  )
$$;

revoke all on function private.has_capability(text) from PUBLIC;
revoke all on function private.has_capability(text) from anon;
revoke all on function private.has_capability(text) from authenticated;
grant execute on function private.has_capability(text) to authenticated;

create table public.audit_events (
  id uuid not null,
  occurred_at timestamptz not null,
  actor_operational_person_id uuid null,
  operational_account_id uuid null,
  capability_id uuid null,
  action_code text not null,
  source_area text not null,
  subject_table text not null,
  subject_id uuid not null,
  cause text null,
  previous_values jsonb null,
  new_values jsonb null,
  created_at timestamptz not null default now(),
  constraint pk_audit_events primary key (id),
  constraint fk_audit_events__operational_people foreign key (actor_operational_person_id) references public.operational_people (id) on delete restrict,
  constraint fk_audit_events__operational_accounts foreign key (operational_account_id) references public.operational_accounts (id) on delete restrict,
  constraint fk_audit_events__capabilities foreign key (capability_id) references public.capabilities (id) on delete restrict,
  constraint ck_audit_events__actor_attribution check (
    (
      actor_operational_person_id is not null
      and operational_account_id is not null
      and capability_id is not null
    )
    or (
      actor_operational_person_id is null
      and operational_account_id is null
      and capability_id is null
    )
  ),
  constraint ck_audit_events__system_cause check (
    (
      actor_operational_person_id is not null
      and operational_account_id is not null
      and capability_id is not null
    )
    or cause is not null
  ),
  constraint ck_audit_events__source_area check (
    source_area in (
      'catalog',
      'access',
      'customer',
      'order',
      'inventory',
      'preparation',
      'delivery',
      'support'
    )
  )
);

alter table public.audit_events enable row level security;

revoke all on table public.audit_events from PUBLIC;
revoke all on table public.audit_events from anon;
revoke all on table public.audit_events from authenticated;

create index ix_audit_events__subject
  on public.audit_events (subject_table, subject_id, occurred_at);

create index ix_audit_events__occurred_at
  on public.audit_events (occurred_at);

create index ix_audit_events__source_area_occurred_at
  on public.audit_events (source_area, occurred_at);

create index ix_audit_events__actor_operational_person_id
  on public.audit_events (actor_operational_person_id)
  where actor_operational_person_id is not null;

create index ix_audit_events__operational_account_id
  on public.audit_events (operational_account_id)
  where operational_account_id is not null;

create index ix_audit_events__capability_id
  on public.audit_events (capability_id)
  where capability_id is not null;
