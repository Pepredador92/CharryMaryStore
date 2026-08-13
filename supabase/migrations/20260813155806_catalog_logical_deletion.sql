alter table public.products
  add column deleted_at timestamptz null,
  add column deletion_reason text null,
  add constraint ck_products__deletion_metadata check (
    (deleted_at is null and deletion_reason is null)
    or (deleted_at is not null and deletion_reason is not null)
  );

alter table public.sellable_presentations
  add column deleted_at timestamptz null,
  add column deletion_reason text null,
  add constraint ck_sellable_presentations__deletion_metadata check (
    (deleted_at is null and deletion_reason is null)
    or (deleted_at is not null and deletion_reason is not null)
  );

create function private.delete_catalog_product(p_product_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_product public.products%rowtype;
  v_inventory record;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_reason text := 'Eliminado desde el panel administrativo';
  v_resource_paths jsonb;
  v_requires_history boolean;
  v_presentation_count bigint;
begin
  select * into v_actor
  from private.resolve_operational_actor(array['catalog.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing catalog.manage capability';
  end if;

  select * into v_product
  from public.products
  where id = p_product_id
  for update;

  if not found or v_product.deleted_at is not null then
    raise exception 'El producto no existe';
  end if;

  select exists (
    select 1
    from public.inventory_movements movement
    join public.sellable_presentations presentation
      on presentation.id = movement.presentation_id
    where presentation.product_id = p_product_id
  ) or exists (
    select 1
    from public.order_items item
    join public.sellable_presentations presentation
      on presentation.id = item.presentation_id
    where presentation.product_id = p_product_id
  ) or exists (
    select 1
    from public.order_item_package_components component
    join public.sellable_presentations presentation
      on presentation.id = component.presentation_id
    where presentation.product_id = p_product_id
  ) or exists (
    select 1
    from public.support_requests request
    where request.product_id = p_product_id
      or request.presentation_id in (
        select id from public.sellable_presentations where product_id = p_product_id
      )
  ) or exists (
    select 1
    from public.presentation_inventory inventory
    join public.sellable_presentations presentation
      on presentation.id = inventory.presentation_id
    where presentation.product_id = p_product_id
      and inventory.on_hand_quantity <> 0
  ) into v_requires_history;

  if v_requires_history and exists (
    select 1
    from public.presentation_inventory inventory
    join public.sellable_presentations presentation
      on presentation.id = inventory.presentation_id
    where presentation.product_id = p_product_id
      and inventory.on_hand_quantity <> 0
  ) and not private.has_capability('inventory.adjust') then
    raise exception 'Se requiere inventory.adjust para retirar las existencias del producto';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(resource.source_reference order by resource.created_at),
    '[]'::jsonb
  ) into v_resource_paths
  from public.catalog_resources resource
  where resource.product_id = p_product_id
     or resource.presentation_id in (
       select id from public.sellable_presentations where product_id = p_product_id
     );

  select pg_catalog.count(*) into v_presentation_count
  from public.sellable_presentations
  where product_id = p_product_id;

  delete from public.cart_lines
  where presentation_id in (
    select id from public.sellable_presentations where product_id = p_product_id
  );

  delete from public.package_components
  where presentation_id in (
    select id from public.sellable_presentations where product_id = p_product_id
  );

  delete from public.catalog_resources resource
  where resource.product_id = p_product_id
     or resource.presentation_id in (
       select id from public.sellable_presentations where product_id = p_product_id
     );

  delete from public.catalog_classification_assignments
  where product_id = p_product_id;

  if v_requires_history then
    for v_inventory in
      select inventory.presentation_id, inventory.on_hand_quantity
      from public.presentation_inventory inventory
      join public.sellable_presentations presentation
        on presentation.id = inventory.presentation_id
      where presentation.product_id = p_product_id
        and inventory.on_hand_quantity <> 0
      order by inventory.presentation_id
      for update of inventory
    loop
      update public.presentation_inventory
      set on_hand_quantity = 0,
          updated_at = v_now
      where presentation_id = v_inventory.presentation_id;

      insert into public.inventory_movements (
        id, presentation_id, quantity_delta, movement_kind,
        order_id, actor_operational_person_id, cause, occurred_at
      ) values (
        pg_catalog.gen_random_uuid(), v_inventory.presentation_id,
        -v_inventory.on_hand_quantity, 'manual_adjustment', null,
        v_actor.operational_person_id,
        'Retiro por eliminación del producto', v_now
      );
    end loop;

    update public.sellable_presentations
    set is_active = false,
        archived_at = coalesce(archived_at, v_now),
        deleted_at = v_now,
        deletion_reason = v_reason,
        updated_at = v_now
    where product_id = p_product_id;

    update public.products
    set is_active = false,
        archived_at = coalesce(archived_at, v_now),
        deleted_at = v_now,
        deletion_reason = v_reason,
        updated_at = v_now
    where id = p_product_id;
  else
    delete from public.presentation_inventory
    where presentation_id in (
      select id from public.sellable_presentations where product_id = p_product_id
    );

    delete from public.sellable_presentations
    where product_id = p_product_id;

    delete from public.products
    where id = p_product_id;
  end if;

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id,
    cause, previous_values, new_values
  ) values (
    pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
    v_actor.operational_account_id, v_actor.capability_id,
    case when v_requires_history then 'catalog.product_logically_deleted' else 'catalog.product_deleted' end,
    'catalog', 'products', p_product_id, v_reason,
    pg_catalog.jsonb_build_object(
      'name', v_product.name,
      'presentation_count', v_presentation_count
    ),
    pg_catalog.jsonb_build_object('deletion_kind', case when v_requires_history then 'logical' else 'physical' end)
  );

  return pg_catalog.jsonb_build_object(
    'product_id', p_product_id,
    'product_name', v_product.name,
    'deletion_kind', case when v_requires_history then 'logical' else 'physical' end,
    'resource_paths', v_resource_paths
  );
end;
$$;

revoke all on function private.delete_catalog_product(uuid) from PUBLIC;
revoke all on function private.delete_catalog_product(uuid) from anon;
revoke all on function private.delete_catalog_product(uuid) from authenticated;
grant execute on function private.delete_catalog_product(uuid) to authenticated;

create function public.delete_catalog_product(p_product_id uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.delete_catalog_product(p_product_id)
$$;

revoke all on function public.delete_catalog_product(uuid) from PUBLIC;
revoke all on function public.delete_catalog_product(uuid) from anon;
revoke all on function public.delete_catalog_product(uuid) from authenticated;
grant execute on function public.delete_catalog_product(uuid) to authenticated;

create function private.delete_catalog_presentation(p_presentation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_presentation public.sellable_presentations%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_reason text := 'Eliminada desde el panel administrativo';
  v_resource_paths jsonb;
  v_current_quantity bigint;
  v_requires_history boolean;
begin
  select * into v_actor
  from private.resolve_operational_actor(array['catalog.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing catalog.manage capability';
  end if;

  select * into v_presentation
  from public.sellable_presentations
  where id = p_presentation_id
  for update;

  if not found or v_presentation.deleted_at is not null then
    raise exception 'La presentación no existe';
  end if;

  select coalesce(on_hand_quantity, 0) into v_current_quantity
  from public.presentation_inventory
  where presentation_id = p_presentation_id
  for update;

  if not found then
    v_current_quantity := 0;
  end if;

  select v_current_quantity <> 0
    or exists (select 1 from public.inventory_movements where presentation_id = p_presentation_id)
    or exists (select 1 from public.order_items where presentation_id = p_presentation_id)
    or exists (select 1 from public.order_item_package_components where presentation_id = p_presentation_id)
    or exists (select 1 from public.support_requests where presentation_id = p_presentation_id)
  into v_requires_history;

  if v_current_quantity <> 0 and not private.has_capability('inventory.adjust') then
    raise exception 'Se requiere inventory.adjust para retirar las existencias de la presentación';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(source_reference order by created_at),
    '[]'::jsonb
  ) into v_resource_paths
  from public.catalog_resources
  where presentation_id = p_presentation_id;

  delete from public.cart_lines
  where presentation_id = p_presentation_id;

  delete from public.package_components
  where presentation_id = p_presentation_id;

  delete from public.catalog_resources
  where presentation_id = p_presentation_id;

  if v_requires_history then
    if v_current_quantity <> 0 then
      update public.presentation_inventory
      set on_hand_quantity = 0,
          updated_at = v_now
      where presentation_id = p_presentation_id;

      insert into public.inventory_movements (
        id, presentation_id, quantity_delta, movement_kind,
        order_id, actor_operational_person_id, cause, occurred_at
      ) values (
        pg_catalog.gen_random_uuid(), p_presentation_id,
        -v_current_quantity, 'manual_adjustment', null,
        v_actor.operational_person_id,
        'Retiro por eliminación de la presentación', v_now
      );
    end if;

    update public.sellable_presentations
    set is_active = false,
        archived_at = coalesce(archived_at, v_now),
        deleted_at = v_now,
        deletion_reason = v_reason,
        updated_at = v_now
    where id = p_presentation_id;
  else
    delete from public.presentation_inventory
    where presentation_id = p_presentation_id;

    delete from public.sellable_presentations
    where id = p_presentation_id;
  end if;

  if not exists (
    select 1
    from public.sellable_presentations
    where product_id = v_presentation.product_id
      and deleted_at is null
      and is_active = true
      and archived_at is null
  ) then
    update public.products
    set is_active = false,
        updated_at = v_now
    where id = v_presentation.product_id;
  end if;

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id,
    cause, previous_values, new_values
  ) values (
    pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
    v_actor.operational_account_id, v_actor.capability_id,
    case when v_requires_history then 'catalog.presentation_logically_deleted' else 'catalog.presentation_deleted' end,
    'catalog', 'sellable_presentations', p_presentation_id, v_reason,
    pg_catalog.jsonb_build_object(
      'sku', v_presentation.sku,
      'product_id', v_presentation.product_id,
      'on_hand_quantity', v_current_quantity
    ),
    pg_catalog.jsonb_build_object('deletion_kind', case when v_requires_history then 'logical' else 'physical' end)
  );

  return pg_catalog.jsonb_build_object(
    'presentation_id', p_presentation_id,
    'product_id', v_presentation.product_id,
    'deletion_kind', case when v_requires_history then 'logical' else 'physical' end,
    'resource_paths', v_resource_paths
  );
end;
$$;

revoke all on function private.delete_catalog_presentation(uuid) from PUBLIC;
revoke all on function private.delete_catalog_presentation(uuid) from anon;
revoke all on function private.delete_catalog_presentation(uuid) from authenticated;
grant execute on function private.delete_catalog_presentation(uuid) to authenticated;

create function public.delete_catalog_presentation(p_presentation_id uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.delete_catalog_presentation(p_presentation_id)
$$;

revoke all on function public.delete_catalog_presentation(uuid) from PUBLIC;
revoke all on function public.delete_catalog_presentation(uuid) from anon;
revoke all on function public.delete_catalog_presentation(uuid) from authenticated;
grant execute on function public.delete_catalog_presentation(uuid) to authenticated;
