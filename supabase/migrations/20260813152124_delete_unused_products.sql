create function private.delete_unused_product(p_product_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_product public.products%rowtype;
  v_resource_paths jsonb;
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

  if not found then
    raise exception 'El producto no existe';
  end if;

  if exists (
    select 1
    from public.presentation_inventory inventory
    join public.sellable_presentations presentation
      on presentation.id = inventory.presentation_id
    where presentation.product_id = p_product_id
      and inventory.on_hand_quantity <> 0
  ) then
    raise exception 'No se puede eliminar: el producto todavía tiene existencias';
  end if;

  if exists (
    select 1
    from public.inventory_movements movement
    join public.sellable_presentations presentation
      on presentation.id = movement.presentation_id
    where presentation.product_id = p_product_id
  ) then
    raise exception 'No se puede eliminar: el producto tiene movimientos de inventario';
  end if;

  if exists (
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
  ) then
    raise exception 'No se puede eliminar: el producto forma parte del historial de pedidos';
  end if;

  if exists (
    select 1
    from public.cart_lines line
    join public.sellable_presentations presentation
      on presentation.id = line.presentation_id
    where presentation.product_id = p_product_id
  ) then
    raise exception 'No se puede eliminar: el producto está agregado en un carrito';
  end if;

  if exists (
    select 1
    from public.package_components component
    join public.sellable_presentations presentation
      on presentation.id = component.presentation_id
    where presentation.product_id = p_product_id
  ) then
    raise exception 'No se puede eliminar: el producto forma parte de un paquete';
  end if;

  if exists (
    select 1
    from public.support_requests request
    where request.product_id = p_product_id
      or request.presentation_id in (
        select id
        from public.sellable_presentations
        where product_id = p_product_id
      )
  ) then
    raise exception 'No se puede eliminar: el producto está vinculado a una conversación de atención';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(resource.source_reference order by resource.created_at),
    '[]'::jsonb
  ) into v_resource_paths
  from public.catalog_resources resource
  where resource.product_id = p_product_id
     or resource.presentation_id in (
       select id
       from public.sellable_presentations
       where product_id = p_product_id
     );

  select pg_catalog.count(*) into v_presentation_count
  from public.sellable_presentations
  where product_id = p_product_id;

  delete from public.catalog_resources resource
  where resource.product_id = p_product_id
     or resource.presentation_id in (
       select id
       from public.sellable_presentations
       where product_id = p_product_id
     );

  delete from public.catalog_classification_assignments
  where product_id = p_product_id;

  delete from public.presentation_inventory inventory
  where inventory.presentation_id in (
    select id
    from public.sellable_presentations
    where product_id = p_product_id
  );

  delete from public.sellable_presentations
  where product_id = p_product_id;

  delete from public.products
  where id = p_product_id;

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
    previous_values,
    new_values
  ) values (
    pg_catalog.gen_random_uuid(),
    pg_catalog.clock_timestamp(),
    v_actor.operational_person_id,
    v_actor.operational_account_id,
    v_actor.capability_id,
    'catalog.product_deleted',
    'catalog',
    'products',
    p_product_id,
    pg_catalog.jsonb_build_object(
      'name', v_product.name,
      'presentation_count', v_presentation_count,
      'resource_paths', v_resource_paths
    ),
    null
  );

  return pg_catalog.jsonb_build_object(
    'product_id', p_product_id,
    'product_name', v_product.name,
    'resource_paths', v_resource_paths
  );
end;
$$;

revoke all on function private.delete_unused_product(uuid) from PUBLIC;
revoke all on function private.delete_unused_product(uuid) from anon;
revoke all on function private.delete_unused_product(uuid) from authenticated;
grant execute on function private.delete_unused_product(uuid) to authenticated;

create function public.delete_unused_product(p_product_id uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.delete_unused_product(p_product_id)
$$;

revoke all on function public.delete_unused_product(uuid) from PUBLIC;
revoke all on function public.delete_unused_product(uuid) from anon;
revoke all on function public.delete_unused_product(uuid) from authenticated;
grant execute on function public.delete_unused_product(uuid) to authenticated;
