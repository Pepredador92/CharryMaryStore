\set ON_ERROR_STOP on

-- Run manually with psql variables. This file is intentionally not a migration.
-- Required variables:
--   auth_user_id, internal_reference, display_name, capability_codes
-- capability_codes must be a JSON array of existing capability codes.

begin;

create temporary table bootstrap_operational_admin_input (
  auth_user_id uuid not null,
  internal_reference text not null,
  display_name text not null,
  capability_codes jsonb not null
) on commit drop;

insert into bootstrap_operational_admin_input (
  auth_user_id,
  internal_reference,
  display_name,
  capability_codes
)
values (
  :'auth_user_id'::uuid,
  :'internal_reference',
  :'display_name',
  :'capability_codes'::jsonb
);

do $$
declare
  v_input bootstrap_operational_admin_input%rowtype;
  v_person_id uuid;
  v_account_id uuid;
  v_unknown_codes text;
begin
  select * into strict v_input from bootstrap_operational_admin_input;

  if nullif(pg_catalog.btrim(v_input.internal_reference), '') is null
    or nullif(pg_catalog.btrim(v_input.display_name), '') is null then
    raise exception 'Internal reference and display name are required';
  end if;

  if pg_catalog.jsonb_typeof(v_input.capability_codes) <> 'array'
    or pg_catalog.jsonb_array_length(v_input.capability_codes) = 0 then
    raise exception 'capability_codes must be a non-empty JSON array';
  end if;

  if not exists (select 1 from auth.users where id = v_input.auth_user_id) then
    raise exception 'The supplied auth.users UUID does not exist';
  end if;

  select pg_catalog.string_agg(requested.code, ', ' order by requested.code)
  into v_unknown_codes
  from (
    select pg_catalog.jsonb_array_elements_text(v_input.capability_codes) as code
  ) requested
  left join public.capabilities on public.capabilities.code = requested.code
    and public.capabilities.is_active
  where public.capabilities.id is null;

  if v_unknown_codes is not null then
    raise exception 'Unknown or inactive capabilities: %', v_unknown_codes;
  end if;

  insert into public.operational_people (
    id, internal_reference, display_name, status, started_at
  ) values (
    pg_catalog.gen_random_uuid(), pg_catalog.btrim(v_input.internal_reference),
    pg_catalog.btrim(v_input.display_name), 'active', pg_catalog.now()
  )
  on conflict on constraint uq_operational_people__internal_reference do update
  set display_name = excluded.display_name,
      status = 'active',
      ended_at = null,
      updated_at = pg_catalog.now();

  select id into v_person_id
  from public.operational_people
  where internal_reference = pg_catalog.btrim(v_input.internal_reference);

  select id, operational_person_id into v_account_id, v_person_id
  from public.operational_accounts
  where auth_user_id = v_input.auth_user_id;

  if found then
    if v_person_id <> (
      select id from public.operational_people
      where internal_reference = pg_catalog.btrim(v_input.internal_reference)
    ) then
      raise exception 'Auth user is already linked to another operational person';
    end if;
    update public.operational_accounts
    set status = 'active', activated_at = coalesce(activated_at, pg_catalog.now()),
        revoked_at = null, updated_at = pg_catalog.now()
    where id = v_account_id;
  else
    select id into v_person_id
    from public.operational_people
    where internal_reference = pg_catalog.btrim(v_input.internal_reference);
    v_account_id := pg_catalog.gen_random_uuid();
    insert into public.operational_accounts (
      id, operational_person_id, auth_user_id, status, activated_at
    ) values (
      v_account_id, v_person_id, v_input.auth_user_id, 'active', pg_catalog.now()
    );
  end if;

  insert into public.operational_account_capabilities (
    id, operational_account_id, capability_id,
    granted_by_person_id, granted_at, reason
  )
  select
    pg_catalog.gen_random_uuid(), v_account_id, capability.id,
    v_person_id, pg_catalog.now(), 'Bootstrap manual del primer administrador'
  from (
    select distinct pg_catalog.jsonb_array_elements_text(v_input.capability_codes) as code
  ) requested
  join public.capabilities capability on capability.code = requested.code and capability.is_active
  where not exists (
    select 1
    from public.operational_account_capabilities existing
    where existing.operational_account_id = v_account_id
      and existing.capability_id = capability.id
      and existing.revoked_at is null
  );
end;
$$;

commit;
