create or replace function public.adjust_presentation_inventory(
  p_presentation_id uuid,
  p_quantity_delta bigint,
  p_movement_kind text,
  p_cause text
)
returns table (
  presentation_id uuid,
  on_hand_quantity bigint,
  movement_id uuid
)
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_operational_person_id uuid;
  v_current_quantity bigint;
  v_new_quantity bigint;
  v_movement_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if not private.has_capability('inventory.adjust') then
    raise exception 'Missing inventory.adjust capability';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Quantity delta must be nonzero';
  end if;

  if p_movement_kind not in ('stock_entry', 'manual_adjustment') then
    raise exception 'Movement kind is not allowed for manual inventory operations';
  end if;

  if p_movement_kind = 'stock_entry' and p_quantity_delta < 0 then
    raise exception 'Stock entry quantity must be positive';
  end if;

  if nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'Cause is required';
  end if;

  perform 1
  from public.sellable_presentations
  where public.sellable_presentations.id = p_presentation_id
  for update;

  if not found then
    raise exception 'Sellable presentation does not exist';
  end if;

  select public.presentation_inventory.on_hand_quantity
  into v_current_quantity
  from public.presentation_inventory
  where public.presentation_inventory.presentation_id = p_presentation_id
  for update;

  if not found then
    v_current_quantity := 0;
  end if;

  v_new_quantity := v_current_quantity + p_quantity_delta;

  if v_new_quantity < 0 then
    raise exception 'Inventory cannot become negative';
  end if;

  insert into public.presentation_inventory (
    presentation_id,
    on_hand_quantity,
    updated_at
  )
  values (
    p_presentation_id,
    v_new_quantity,
    pg_catalog.now()
  )
  on conflict on constraint pk_presentation_inventory do update
  set
    on_hand_quantity = excluded.on_hand_quantity,
    updated_at = excluded.updated_at;

  v_actor_operational_person_id := private.current_operational_person_id();
  v_movement_id := pg_catalog.gen_random_uuid();

  insert into public.inventory_movements (
    id,
    presentation_id,
    quantity_delta,
    movement_kind,
    order_id,
    actor_operational_person_id,
    cause,
    occurred_at
  )
  values (
    v_movement_id,
    p_presentation_id,
    p_quantity_delta,
    p_movement_kind,
    null,
    v_actor_operational_person_id,
    pg_catalog.btrim(p_cause),
    pg_catalog.now()
  );

  return query
  select p_presentation_id, v_new_quantity, v_movement_id;
end;
$$;

revoke all on function public.adjust_presentation_inventory(uuid, bigint, text, text) from PUBLIC;
revoke all on function public.adjust_presentation_inventory(uuid, bigint, text, text) from anon;
revoke all on function public.adjust_presentation_inventory(uuid, bigint, text, text) from authenticated;
grant execute on function public.adjust_presentation_inventory(uuid, bigint, text, text) to authenticated;
