create function private.operational_access_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_capabilities jsonb;
  v_accounts jsonb;
begin
  select *
  into v_actor
  from private.resolve_operational_actor(array['access.read', 'access.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing access.read or access.manage capability';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', public.capabilities.id,
        'code', public.capabilities.code,
        'name', public.capabilities.name,
        'description', public.capabilities.description
      )
      order by public.capabilities.code
    ),
    '[]'::jsonb
  )
  into v_capabilities
  from public.capabilities
  where public.capabilities.is_active = true;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'account_id', account.id,
        'person_id', person.id,
        'internal_reference', person.internal_reference,
        'display_name', person.display_name,
        'email', auth_user.email,
        'person_status', person.status,
        'account_status', account.status,
        'activated_at', account.activated_at,
        'revoked_at', account.revoked_at,
        'created_at', account.created_at,
        'is_current', account.id = v_actor.operational_account_id,
        'capability_codes', coalesce((
          select pg_catalog.jsonb_agg(capability.code order by capability.code)
          from public.operational_account_capabilities assignment
          join public.capabilities capability
            on capability.id = assignment.capability_id
          where assignment.operational_account_id = account.id
            and assignment.revoked_at is null
            and capability.is_active = true
        ), '[]'::jsonb)
      )
      order by person.display_name, person.internal_reference
    ),
    '[]'::jsonb
  )
  into v_accounts
  from public.operational_accounts account
  join public.operational_people person
    on person.id = account.operational_person_id
  join auth.users auth_user
    on auth_user.id = account.auth_user_id;

  return pg_catalog.jsonb_build_object(
    'current_account_id', v_actor.operational_account_id,
    'capabilities', v_capabilities,
    'accounts', v_accounts
  );
end;
$$;

revoke all on function private.operational_access_snapshot() from PUBLIC;
revoke all on function private.operational_access_snapshot() from anon;
revoke all on function private.operational_access_snapshot() from authenticated;
grant execute on function private.operational_access_snapshot() to authenticated;

create function public.operational_access_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select private.operational_access_snapshot()
$$;

revoke all on function public.operational_access_snapshot() from PUBLIC;
revoke all on function public.operational_access_snapshot() from anon;
revoke all on function public.operational_access_snapshot() from authenticated;
grant execute on function public.operational_access_snapshot() to authenticated;

create function private.create_operational_access(
  p_email text,
  p_internal_reference text,
  p_display_name text,
  p_capability_codes text[],
  p_cause text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_auth_user_id uuid;
  v_person_id uuid := pg_catalog.gen_random_uuid();
  v_account_id uuid := pg_catalog.gen_random_uuid();
  v_codes text[];
  v_unknown_codes text;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select *
  into v_actor
  from private.resolve_operational_actor(array['access.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing access.manage capability';
  end if;

  if nullif(pg_catalog.btrim(p_email), '') is null
    or nullif(pg_catalog.btrim(p_internal_reference), '') is null
    or nullif(pg_catalog.btrim(p_display_name), '') is null
    or nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'Email, internal reference, display name and cause are required';
  end if;

  select pg_catalog.array_agg(requested.code order by requested.code)
  into v_codes
  from (
    select distinct pg_catalog.btrim(value) as code
    from pg_catalog.unnest(p_capability_codes) as requested(value)
    where nullif(pg_catalog.btrim(value), '') is not null
  ) requested;

  if coalesce(pg_catalog.cardinality(v_codes), 0) = 0 then
    raise exception 'At least one capability is required';
  end if;

  select pg_catalog.string_agg(requested.code, ', ' order by requested.code)
  into v_unknown_codes
  from pg_catalog.unnest(v_codes) as requested(code)
  left join public.capabilities capability
    on capability.code = requested.code
    and capability.is_active = true
  where capability.id is null;

  if v_unknown_codes is not null then
    raise exception 'Unknown or inactive capabilities: %', v_unknown_codes;
  end if;

  select auth_user.id
  into v_auth_user_id
  from auth.users auth_user
  where pg_catalog.lower(auth_user.email) = pg_catalog.lower(pg_catalog.btrim(p_email));

  if v_auth_user_id is null then
    raise exception 'The user must sign in once before operational access can be granted';
  end if;

  if exists (
    select 1
    from public.operational_accounts account
    where account.auth_user_id = v_auth_user_id
  ) then
    raise exception 'The authenticated user already has an operational account';
  end if;

  if exists (
    select 1
    from public.operational_people person
    where person.internal_reference = pg_catalog.btrim(p_internal_reference)
  ) then
    raise exception 'The internal reference is already in use';
  end if;

  insert into public.operational_people (
    id,
    internal_reference,
    display_name,
    status,
    started_at
  ) values (
    v_person_id,
    pg_catalog.btrim(p_internal_reference),
    pg_catalog.btrim(p_display_name),
    'active',
    v_now
  );

  insert into public.operational_accounts (
    id,
    operational_person_id,
    auth_user_id,
    status,
    activated_at
  ) values (
    v_account_id,
    v_person_id,
    v_auth_user_id,
    'active',
    v_now
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
    v_account_id,
    capability.id,
    v_actor.operational_person_id,
    v_now,
    pg_catalog.btrim(p_cause)
  from public.capabilities capability
  where capability.code = any (v_codes)
    and capability.is_active = true;

  insert into public.audit_events (
    id,
    occurred_at,
    actor_operational_person_id,
    operational_account_id,
    capability_id,
    action_code,
    source_area,
    subject_table,
    subject_id,
    cause,
    new_values
  ) values (
    pg_catalog.gen_random_uuid(),
    v_now,
    v_actor.operational_person_id,
    v_actor.operational_account_id,
    v_actor.capability_id,
    'access.operational_account_created',
    'access',
    'operational_accounts',
    v_account_id,
    pg_catalog.btrim(p_cause),
    pg_catalog.jsonb_build_object(
      'internal_reference', pg_catalog.btrim(p_internal_reference),
      'display_name', pg_catalog.btrim(p_display_name),
      'capability_codes', pg_catalog.to_jsonb(v_codes)
    )
  );

  return v_account_id;
end;
$$;

revoke all on function private.create_operational_access(text, text, text, text[], text) from PUBLIC;
revoke all on function private.create_operational_access(text, text, text, text[], text) from anon;
revoke all on function private.create_operational_access(text, text, text, text[], text) from authenticated;
grant execute on function private.create_operational_access(text, text, text, text[], text) to authenticated;

create function public.create_operational_access(
  p_email text,
  p_internal_reference text,
  p_display_name text,
  p_capability_codes text[],
  p_cause text
)
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.create_operational_access(
    p_email,
    p_internal_reference,
    p_display_name,
    p_capability_codes,
    p_cause
  )
$$;

revoke all on function public.create_operational_access(text, text, text, text[], text) from PUBLIC;
revoke all on function public.create_operational_access(text, text, text, text[], text) from anon;
revoke all on function public.create_operational_access(text, text, text, text[], text) from authenticated;
grant execute on function public.create_operational_access(text, text, text, text[], text) to authenticated;

create function private.set_operational_access_capabilities(
  p_account_id uuid,
  p_capability_codes text[],
  p_cause text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_target_person_id uuid;
  v_codes text[];
  v_previous_codes text[];
  v_unknown_codes text;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select *
  into v_actor
  from private.resolve_operational_actor(array['access.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing access.manage capability';
  end if;

  if p_account_id is null or nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'Operational account and cause are required';
  end if;

  select account.operational_person_id
  into v_target_person_id
  from public.operational_accounts account
  where account.id = p_account_id
    and account.revoked_at is null;

  if v_target_person_id is null then
    raise exception 'Operational account does not exist or is revoked';
  end if;

  select pg_catalog.array_agg(requested.code order by requested.code)
  into v_codes
  from (
    select distinct pg_catalog.btrim(value) as code
    from pg_catalog.unnest(p_capability_codes) as requested(value)
    where nullif(pg_catalog.btrim(value), '') is not null
  ) requested;

  if coalesce(pg_catalog.cardinality(v_codes), 0) = 0 then
    raise exception 'At least one capability is required';
  end if;

  select pg_catalog.string_agg(requested.code, ', ' order by requested.code)
  into v_unknown_codes
  from pg_catalog.unnest(v_codes) as requested(code)
  left join public.capabilities capability
    on capability.code = requested.code
    and capability.is_active = true
  where capability.id is null;

  if v_unknown_codes is not null then
    raise exception 'Unknown or inactive capabilities: %', v_unknown_codes;
  end if;

  if p_account_id = v_actor.operational_account_id
    and not ('access.manage' = any (v_codes)) then
    raise exception 'You cannot remove access.manage from your current account';
  end if;

  select pg_catalog.array_agg(capability.code order by capability.code)
  into v_previous_codes
  from public.operational_account_capabilities assignment
  join public.capabilities capability
    on capability.id = assignment.capability_id
  where assignment.operational_account_id = p_account_id
    and assignment.revoked_at is null
    and capability.is_active = true;

  update public.operational_account_capabilities assignment
  set
    revoked_at = v_now,
    reason = pg_catalog.btrim(p_cause)
  where assignment.operational_account_id = p_account_id
    and assignment.revoked_at is null
    and not exists (
      select 1
      from public.capabilities capability
      where capability.id = assignment.capability_id
        and capability.code = any (v_codes)
        and capability.is_active = true
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
    p_account_id,
    capability.id,
    v_actor.operational_person_id,
    v_now,
    pg_catalog.btrim(p_cause)
  from public.capabilities capability
  where capability.code = any (v_codes)
    and capability.is_active = true
    and not exists (
      select 1
      from public.operational_account_capabilities assignment
      where assignment.operational_account_id = p_account_id
        and assignment.capability_id = capability.id
        and assignment.revoked_at is null
    );

  update public.operational_accounts
  set updated_at = v_now
  where id = p_account_id;

  insert into public.audit_events (
    id,
    occurred_at,
    actor_operational_person_id,
    operational_account_id,
    capability_id,
    action_code,
    source_area,
    subject_table,
    subject_id,
    cause,
    previous_values,
    new_values
  ) values (
    pg_catalog.gen_random_uuid(),
    v_now,
    v_actor.operational_person_id,
    v_actor.operational_account_id,
    v_actor.capability_id,
    'access.capabilities_updated',
    'access',
    'operational_accounts',
    p_account_id,
    pg_catalog.btrim(p_cause),
    pg_catalog.jsonb_build_object(
      'capability_codes', pg_catalog.to_jsonb(coalesce(v_previous_codes, array[]::text[]))
    ),
    pg_catalog.jsonb_build_object(
      'capability_codes', pg_catalog.to_jsonb(v_codes)
    )
  );
end;
$$;

revoke all on function private.set_operational_access_capabilities(uuid, text[], text) from PUBLIC;
revoke all on function private.set_operational_access_capabilities(uuid, text[], text) from anon;
revoke all on function private.set_operational_access_capabilities(uuid, text[], text) from authenticated;
grant execute on function private.set_operational_access_capabilities(uuid, text[], text) to authenticated;

create function public.set_operational_access_capabilities(
  p_account_id uuid,
  p_capability_codes text[],
  p_cause text
)
returns void
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.set_operational_access_capabilities(
    p_account_id,
    p_capability_codes,
    p_cause
  )
$$;

revoke all on function public.set_operational_access_capabilities(uuid, text[], text) from PUBLIC;
revoke all on function public.set_operational_access_capabilities(uuid, text[], text) from anon;
revoke all on function public.set_operational_access_capabilities(uuid, text[], text) from authenticated;
grant execute on function public.set_operational_access_capabilities(uuid, text[], text) to authenticated;

create function private.set_operational_access_status(
  p_account_id uuid,
  p_status text,
  p_cause text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_person_id uuid;
  v_previous_account_status text;
  v_previous_person_status text;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select *
  into v_actor
  from private.resolve_operational_actor(array['access.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing access.manage capability';
  end if;

  if p_account_id is null or nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'Operational account and cause are required';
  end if;

  if p_status not in ('active', 'suspended') then
    raise exception 'Unsupported operational account status';
  end if;

  select
    account.operational_person_id,
    account.status,
    person.status
  into
    v_person_id,
    v_previous_account_status,
    v_previous_person_status
  from public.operational_accounts account
  join public.operational_people person
    on person.id = account.operational_person_id
  where account.id = p_account_id
    and account.revoked_at is null;

  if v_person_id is null then
    raise exception 'Operational account does not exist or is revoked';
  end if;

  if p_account_id = v_actor.operational_account_id and p_status <> 'active' then
    raise exception 'You cannot suspend your current operational account';
  end if;

  update public.operational_accounts
  set
    status = p_status,
    activated_at = case
      when p_status = 'active' then coalesce(activated_at, v_now)
      else activated_at
    end,
    updated_at = v_now
  where id = p_account_id;

  update public.operational_people
  set
    status = p_status,
    ended_at = case when p_status = 'active' then null else ended_at end,
    updated_at = v_now
  where id = v_person_id;

  insert into public.audit_events (
    id,
    occurred_at,
    actor_operational_person_id,
    operational_account_id,
    capability_id,
    action_code,
    source_area,
    subject_table,
    subject_id,
    cause,
    previous_values,
    new_values
  ) values (
    pg_catalog.gen_random_uuid(),
    v_now,
    v_actor.operational_person_id,
    v_actor.operational_account_id,
    v_actor.capability_id,
    'access.status_updated',
    'access',
    'operational_accounts',
    p_account_id,
    pg_catalog.btrim(p_cause),
    pg_catalog.jsonb_build_object(
      'account_status', v_previous_account_status,
      'person_status', v_previous_person_status
    ),
    pg_catalog.jsonb_build_object(
      'account_status', p_status,
      'person_status', p_status
    )
  );
end;
$$;

revoke all on function private.set_operational_access_status(uuid, text, text) from PUBLIC;
revoke all on function private.set_operational_access_status(uuid, text, text) from anon;
revoke all on function private.set_operational_access_status(uuid, text, text) from authenticated;
grant execute on function private.set_operational_access_status(uuid, text, text) to authenticated;

create function public.set_operational_access_status(
  p_account_id uuid,
  p_status text,
  p_cause text
)
returns void
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.set_operational_access_status(
    p_account_id,
    p_status,
    p_cause
  )
$$;

revoke all on function public.set_operational_access_status(uuid, text, text) from PUBLIC;
revoke all on function public.set_operational_access_status(uuid, text, text) from anon;
revoke all on function public.set_operational_access_status(uuid, text, text) from authenticated;
grant execute on function public.set_operational_access_status(uuid, text, text) to authenticated;
