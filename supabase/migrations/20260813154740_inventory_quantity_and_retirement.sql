create function private.retire_inventory_presentation(
  p_presentation_id uuid,
  p_cause text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_presentation public.sellable_presentations%rowtype;
  v_current_quantity bigint;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor
  from private.resolve_operational_actor(array['inventory.adjust']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing inventory.adjust capability';
  end if;

  if not private.has_capability('catalog.manage') then
    raise exception 'Missing catalog.manage capability';
  end if;

  if nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'La causa es obligatoria';
  end if;

  select * into v_presentation
  from public.sellable_presentations
  where id = p_presentation_id
  for update;

  if not found then
    raise exception 'La presentación no existe';
  end if;

  if v_presentation.archived_at is not null then
    raise exception 'La presentación ya fue retirada del inventario';
  end if;

  select on_hand_quantity into v_current_quantity
  from public.presentation_inventory
  where presentation_id = p_presentation_id
  for update;

  if not found then
    v_current_quantity := 0;
  end if;

  insert into public.presentation_inventory (
    presentation_id,
    on_hand_quantity,
    updated_at
  ) values (
    p_presentation_id,
    0,
    v_now
  )
  on conflict on constraint pk_presentation_inventory do update
  set on_hand_quantity = excluded.on_hand_quantity,
      updated_at = excluded.updated_at;

  if v_current_quantity <> 0 then
    insert into public.inventory_movements (
      id,
      presentation_id,
      quantity_delta,
      movement_kind,
      order_id,
      actor_operational_person_id,
      cause,
      occurred_at
    ) values (
      pg_catalog.gen_random_uuid(),
      p_presentation_id,
      -v_current_quantity,
      'manual_adjustment',
      null,
      v_actor.operational_person_id,
      'Retiro del inventario: ' || pg_catalog.btrim(p_cause),
      v_now
    );
  end if;

  update public.sellable_presentations
  set is_active = false,
      archived_at = v_now,
      updated_at = v_now
  where id = p_presentation_id;

  if not exists (
    select 1
    from public.sellable_presentations
    where product_id = v_presentation.product_id
      and id <> p_presentation_id
      and is_active = true
      and archived_at is null
  ) then
    update public.products
    set is_active = false,
        updated_at = v_now
    where id = v_presentation.product_id;
  end if;

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
    'inventory.presentation_retired',
    'inventory',
    'sellable_presentations',
    p_presentation_id,
    pg_catalog.btrim(p_cause),
    pg_catalog.jsonb_build_object(
      'is_active', v_presentation.is_active,
      'archived_at', v_presentation.archived_at,
      'on_hand_quantity', v_current_quantity
    ),
    pg_catalog.jsonb_build_object(
      'is_active', false,
      'archived_at', v_now,
      'on_hand_quantity', 0
    )
  );

  return pg_catalog.jsonb_build_object(
    'presentation_id', p_presentation_id,
    'product_id', v_presentation.product_id,
    'removed_quantity', v_current_quantity
  );
end;
$$;

revoke all on function private.retire_inventory_presentation(uuid, text) from PUBLIC;
revoke all on function private.retire_inventory_presentation(uuid, text) from anon;
revoke all on function private.retire_inventory_presentation(uuid, text) from authenticated;
grant execute on function private.retire_inventory_presentation(uuid, text) to authenticated;

create function public.retire_inventory_presentation(
  p_presentation_id uuid,
  p_cause text
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.retire_inventory_presentation(p_presentation_id, p_cause)
$$;

revoke all on function public.retire_inventory_presentation(uuid, text) from PUBLIC;
revoke all on function public.retire_inventory_presentation(uuid, text) from anon;
revoke all on function public.retire_inventory_presentation(uuid, text) from authenticated;
grant execute on function public.retire_inventory_presentation(uuid, text) to authenticated;
