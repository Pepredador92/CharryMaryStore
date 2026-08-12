begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(p_condition, false) then
    raise exception 'Assertion failed: %', p_message;
  end if;
end;
$$;

insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  (
    '11000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'access-manager@test.invalid',
    now(),
    now()
  ),
  (
    '11000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'new-operator@test.invalid',
    now(),
    now()
  ),
  (
    '11000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'unauthorized@test.invalid',
    now(),
    now()
  );

insert into public.operational_people (
  id,
  internal_reference,
  display_name,
  status,
  started_at
)
values (
  '21000000-0000-0000-0000-000000000001',
  'ACCESS-TEST-MANAGER',
  'Access manager',
  'active',
  now()
);

insert into public.operational_accounts (
  id,
  operational_person_id,
  auth_user_id,
  status,
  activated_at
)
values (
  '31000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000001',
  'active',
  now()
);

insert into public.operational_account_capabilities (
  id,
  operational_account_id,
  capability_id,
  granted_by_person_id,
  granted_at,
  reason
)
select
  pg_catalog.gen_random_uuid(),
  '31000000-0000-0000-0000-000000000001',
  capability.id,
  '21000000-0000-0000-0000-000000000001',
  now(),
  'Operational access test'
from public.capabilities capability
where capability.code in ('access.read', 'access.manage');

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '11000000-0000-0000-0000-000000000003',
  true
);

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.create_operational_access(
      'new-operator@test.invalid',
      'ACCESS-TEST-OPERATOR',
      'New operator',
      array['catalog.read'],
      'Unauthorized attempt'
    );
  exception when others then
    v_rejected := true;
  end;

  perform pg_temp.assert_true(
    v_rejected,
    'authenticated user without access.manage must be rejected'
  );
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '11000000-0000-0000-0000-000000000001',
  true
);

select public.create_operational_access(
  'new-operator@test.invalid',
  'ACCESS-TEST-OPERATOR',
  'New operator',
  array['catalog.read', 'catalog.manage'],
  'Authorized creation test'
);

select pg_temp.assert_true(
  exists (
    select 1
    from public.operational_accounts account
    join public.operational_people person
      on person.id = account.operational_person_id
    where account.auth_user_id = '11000000-0000-0000-0000-000000000002'
      and account.status = 'active'
      and account.activated_at is not null
      and account.revoked_at is null
      and person.internal_reference = 'ACCESS-TEST-OPERATOR'
      and person.status = 'active'
  ),
  'authorized creation must create an active operational identity'
);

select pg_temp.assert_true(
  (
    select count(*) = 2
    from public.operational_account_capabilities assignment
    join public.operational_accounts account
      on account.id = assignment.operational_account_id
    where account.auth_user_id = '11000000-0000-0000-0000-000000000002'
      and assignment.revoked_at is null
  ),
  'authorized creation must grant the requested capabilities'
);

select pg_temp.assert_true(
  (
    select exists (
      select 1
      from pg_catalog.jsonb_array_elements(snapshot->'accounts') account
      where account->>'internal_reference' = 'ACCESS-TEST-OPERATOR'
        and account->>'email' = 'new-operator@test.invalid'
    )
    from (
      select public.operational_access_snapshot() as snapshot
    ) result
  ),
  'access snapshot must list the new operational account'
);

select public.set_operational_access_capabilities(
  (
    select id
    from public.operational_accounts
    where auth_user_id = '11000000-0000-0000-0000-000000000002'
  ),
  array['orders.read'],
  'Capability replacement test'
);

select pg_temp.assert_true(
  (
    select pg_catalog.array_agg(capability.code order by capability.code) = array['orders.read']
    from public.operational_account_capabilities assignment
    join public.operational_accounts account
      on account.id = assignment.operational_account_id
    join public.capabilities capability
      on capability.id = assignment.capability_id
    where account.auth_user_id = '11000000-0000-0000-0000-000000000002'
      and assignment.revoked_at is null
  ),
  'capability replacement must leave only requested active assignments'
);

select public.set_operational_access_status(
  (
    select id
    from public.operational_accounts
    where auth_user_id = '11000000-0000-0000-0000-000000000002'
  ),
  'suspended',
  'Suspension test'
);

select pg_temp.assert_true(
  exists (
    select 1
    from public.operational_accounts account
    join public.operational_people person
      on person.id = account.operational_person_id
    where account.auth_user_id = '11000000-0000-0000-0000-000000000002'
      and account.status = 'suspended'
      and person.status = 'suspended'
  ),
  'suspension must affect the operational account and person'
);

select public.set_operational_access_status(
  (
    select id
    from public.operational_accounts
    where auth_user_id = '11000000-0000-0000-0000-000000000002'
  ),
  'active',
  'Reactivation test'
);

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.set_operational_access_status(
      '31000000-0000-0000-0000-000000000001',
      'suspended',
      'Self suspension attempt'
    );
  exception when others then
    v_rejected := true;
  end;

  perform pg_temp.assert_true(
    v_rejected,
    'access manager must not suspend the current account'
  );
end;
$$;

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.set_operational_access_capabilities(
      '31000000-0000-0000-0000-000000000001',
      array['access.read'],
      'Self lockout attempt'
    );
  exception when others then
    v_rejected := true;
  end;

  perform pg_temp.assert_true(
    v_rejected,
    'access manager must not remove access.manage from the current account'
  );
end;
$$;

reset role;

select pg_temp.assert_true(
  (
    select count(*) = 4
    from public.audit_events event
    where source_area = 'access'
      and action_code in (
        'access.operational_account_created',
        'access.capabilities_updated',
        'access.status_updated'
      )
      and event.subject_id = (
        select id
        from public.operational_accounts
        where auth_user_id = '11000000-0000-0000-0000-000000000002'
      )
  ),
  'authorized access changes must be audited'
);

rollback;
