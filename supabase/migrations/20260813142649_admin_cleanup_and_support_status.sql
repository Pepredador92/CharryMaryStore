alter table public.orders
  add column archived_at timestamptz null,
  add column archive_reason text null,
  add column inventory_restored_at timestamptz null,
  add constraint ck_orders__archive_metadata check (
    (archived_at is null and archive_reason is null)
    or (archived_at is not null and archive_reason is not null)
  ),
  add constraint ck_orders__inventory_restored check (
    inventory_restored_at is null
    or (
      archived_at is not null
      and preparation_authorized_at is not null
      and inventory_restored_at >= archived_at
    )
  );

create index ix_orders__active_placed_at
  on public.orders (placed_at desc)
  where archived_at is null;

create or replace function private.admin_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select pg_catalog.jsonb_build_object(
    'orders_pending', case when private.has_capability('orders.read') or private.has_capability('orders.manage')
      then (select pg_catalog.count(*) from public.orders where commercial_status = 'pending_confirmation' and archived_at is null) else null end,
    'orders_confirmed', case when private.has_capability('orders.read') or private.has_capability('orders.manage')
      then (select pg_catalog.count(*) from public.orders where commercial_status = 'confirmed' and archived_at is null) else null end,
    'preparations_pending', case when private.has_capability('preparation.read') or private.has_capability('preparation.manage') or private.has_capability('preparation.operate')
      then (select pg_catalog.count(*) from public.preparations preparation join public.orders on public.orders.id = preparation.order_id where preparation.status = 'pending' and public.orders.archived_at is null) else null end,
    'preparations_in_progress', case when private.has_capability('preparation.read') or private.has_capability('preparation.manage') or private.has_capability('preparation.operate')
      then (select pg_catalog.count(*) from public.preparations preparation join public.orders on public.orders.id = preparation.order_id where preparation.status in ('in_progress', 'reopened') and public.orders.archived_at is null) else null end,
    'preparations_blocked', case when private.has_capability('preparation.read') or private.has_capability('preparation.manage') or private.has_capability('preparation.operate')
      then (select pg_catalog.count(*) from public.preparations preparation join public.orders on public.orders.id = preparation.order_id where preparation.status = 'blocked' and public.orders.archived_at is null) else null end,
    'deliveries_pending', case when private.has_capability('delivery.read') or private.has_capability('delivery.manage') or private.has_capability('delivery.operate')
      then (select pg_catalog.count(*) from public.deliveries delivery join public.orders on public.orders.id = delivery.order_id where delivery.status = 'pending' and public.orders.archived_at is null) else null end,
    'deliveries_active', case when private.has_capability('delivery.read') or private.has_capability('delivery.manage') or private.has_capability('delivery.operate')
      then (select pg_catalog.count(*) from public.deliveries delivery join public.orders on public.orders.id = delivery.order_id where delivery.status in ('in_custody', 'in_transit', 'blocked', 'reopened') and public.orders.archived_at is null) else null end,
    'support_open', case when private.has_capability('support.handle')
      then (select pg_catalog.count(*) from public.support_requests where status in ('open', 'in_attention', 'channelled') and deleted_at is null) else null end,
    'low_inventory', case when private.has_capability('inventory.read') or private.has_capability('inventory.adjust')
      then (select pg_catalog.count(*) from public.presentation_inventory where on_hand_quantity <= 5) else null end
  )
  where private.current_operational_account_id() is not null
$$;

create function private.support_reference_options()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_result jsonb;
begin
  if not private.has_capability('support.handle') then
    raise exception 'Missing support.handle capability';
  end if;

  select pg_catalog.jsonb_build_object(
    'orders', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', public.orders.id,
          'order_number', public.orders.order_number,
          'status', public.orders.commercial_status
        ) order by public.orders.placed_at desc
      )
      from public.orders
      where public.orders.archived_at is null
    ), '[]'::jsonb),
    'preparations', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', preparation.id,
          'order_number', public.orders.order_number,
          'status', preparation.status
        ) order by preparation.created_at desc
      )
      from public.preparations preparation
      join public.orders on public.orders.id = preparation.order_id
      where public.orders.archived_at is null
    ), '[]'::jsonb),
    'deliveries', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', delivery.id,
          'order_number', public.orders.order_number,
          'status', delivery.status
        ) order by delivery.recognized_at desc
      )
      from public.deliveries delivery
      join public.orders on public.orders.id = delivery.order_id
      where public.orders.archived_at is null
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function private.support_reference_options() from PUBLIC;
revoke all on function private.support_reference_options() from anon;
revoke all on function private.support_reference_options() from authenticated;
grant execute on function private.support_reference_options() to authenticated;

create function public.support_reference_options()
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select private.support_reference_options()
$$;

revoke all on function public.support_reference_options() from PUBLIC;
revoke all on function public.support_reference_options() from anon;
revoke all on function public.support_reference_options() from authenticated;
grant execute on function public.support_reference_options() to authenticated;

create or replace function private.set_support_request_status(
  p_request_id uuid,
  p_status text,
  p_cause text default null,
  p_reference_kind text default null,
  p_reference_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_request public.support_requests%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_is_sensitive boolean;
  v_product_id uuid;
  v_presentation_id uuid;
  v_package_id uuid;
  v_order_id uuid;
  v_preparation_id uuid;
  v_delivery_id uuid;
  v_retention_class text;
begin
  select * into v_actor from private.resolve_operational_actor(array['support.handle']);
  if v_actor.operational_account_id is null then raise exception 'Missing support.handle capability'; end if;
  if p_status not in ('open', 'in_attention', 'resolved', 'channelled', 'closed') then raise exception 'Unsupported support status'; end if;

  select * into v_request from public.support_requests where id = p_request_id for update;
  if not found or v_request.deleted_at is not null then raise exception 'Support request does not exist'; end if;

  select exists (
    select 1 from public.support_messages
    where support_request_id = p_request_id and is_sensitive
  ) into v_is_sensitive;
  if v_is_sensitive and not private.has_capability('support.sensitive') then
    raise exception 'support.sensitive is required for this request';
  end if;
  if p_status = 'closed' and nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'Closure reason is required';
  end if;

  v_product_id := v_request.product_id;
  v_presentation_id := v_request.presentation_id;
  v_package_id := v_request.package_id;
  v_order_id := v_request.order_id;
  v_preparation_id := v_request.preparation_id;
  v_delivery_id := v_request.delivery_id;

  if p_reference_kind is not null and p_reference_kind <> 'keep' then
    v_product_id := null;
    v_presentation_id := null;
    v_package_id := null;
    v_order_id := null;
    v_preparation_id := null;
    v_delivery_id := null;

    if p_reference_kind = 'none' then
      if p_reference_id is not null then raise exception 'No reference id is allowed when clearing the link'; end if;
    elsif p_reference_id is null then
      raise exception 'Choose an operational reference';
    elsif p_reference_kind = 'order' then
      if not exists (select 1 from public.orders where id = p_reference_id and archived_at is null) then raise exception 'Order does not exist'; end if;
      v_order_id := p_reference_id;
    elsif p_reference_kind = 'preparation' then
      if not exists (
        select 1 from public.preparations preparation
        join public.orders on public.orders.id = preparation.order_id
        where preparation.id = p_reference_id and public.orders.archived_at is null
      ) then raise exception 'Preparation does not exist'; end if;
      v_preparation_id := p_reference_id;
    elsif p_reference_kind = 'delivery' then
      if not exists (
        select 1 from public.deliveries delivery
        join public.orders on public.orders.id = delivery.order_id
        where delivery.id = p_reference_id and public.orders.archived_at is null
      ) then raise exception 'Delivery does not exist'; end if;
      v_delivery_id := p_reference_id;
    else
      raise exception 'Unsupported operational reference';
    end if;
  elsif p_reference_id is not null then
    raise exception 'Reference kind and id must be provided together';
  end if;

  v_retention_class := case
    when v_order_id is not null or v_preparation_id is not null or v_delivery_id is not null then '90_day'
    else '14_day'
  end;

  update public.support_requests
  set product_id = v_product_id,
      presentation_id = v_presentation_id,
      package_id = v_package_id,
      order_id = v_order_id,
      preparation_id = v_preparation_id,
      delivery_id = v_delivery_id,
      status = p_status,
      closed_at = case when p_status = 'closed' then v_now else null end,
      closure_reason = case when p_status = 'closed' then pg_catalog.btrim(p_cause) else null end,
      retention_class = v_retention_class,
      retention_due_at = case when p_status = 'closed' then
        v_now + case v_retention_class when '14_day' then interval '14 days' else interval '90 days' end
        else null end,
      updated_at = v_now
  where id = p_request_id;

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id, cause,
    previous_values, new_values
  ) values (
    pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
    v_actor.operational_account_id, v_actor.capability_id,
    'support.status_changed', 'support', 'support_requests', p_request_id,
    nullif(pg_catalog.btrim(p_cause), ''),
    pg_catalog.jsonb_build_object('status', v_request.status),
    pg_catalog.jsonb_build_object('status', p_status, 'reference_kind', p_reference_kind)
  );

  return pg_catalog.jsonb_build_object(
    'request_id', p_request_id,
    'status', p_status,
    'retention_due_at', case when p_status = 'closed' then
      v_now + case v_retention_class when '14_day' then interval '14 days' else interval '90 days' end
      else null end
  );
end;
$$;

create function private.delete_support_request(
  p_request_id uuid,
  p_reason text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_request public.support_requests%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor from private.resolve_operational_actor(array['support.handle']);
  if v_actor.operational_account_id is null then raise exception 'Missing support.handle capability'; end if;
  if nullif(pg_catalog.btrim(p_reason), '') is null then raise exception 'Deletion reason is required'; end if;

  select * into v_request from public.support_requests where id = p_request_id for update;
  if not found or v_request.deleted_at is not null then raise exception 'Active support request does not exist'; end if;
  if exists (
    select 1 from public.support_messages
    where support_request_id = p_request_id and is_sensitive
  ) and not private.has_capability('support.sensitive') then
    raise exception 'support.sensitive is required for this request';
  end if;

  update public.support_requests
  set deleted_at = v_now, updated_at = v_now
  where id = p_request_id;

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id, cause,
    previous_values, new_values
  ) values (
    pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
    v_actor.operational_account_id, v_actor.capability_id,
    'support.logically_deleted', 'support', 'support_requests', p_request_id,
    pg_catalog.btrim(p_reason),
    pg_catalog.jsonb_build_object('deleted_at', null),
    pg_catalog.jsonb_build_object('deleted_at', v_now)
  );

  return p_request_id;
end;
$$;

revoke all on function private.delete_support_request(uuid, text) from PUBLIC;
revoke all on function private.delete_support_request(uuid, text) from anon;
revoke all on function private.delete_support_request(uuid, text) from authenticated;
grant execute on function private.delete_support_request(uuid, text) to authenticated;

create function public.delete_support_request(p_request_id uuid, p_reason text)
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.delete_support_request(p_request_id, p_reason)
$$;

revoke all on function public.delete_support_request(uuid, text) from PUBLIC;
revoke all on function public.delete_support_request(uuid, text) from anon;
revoke all on function public.delete_support_request(uuid, text) from authenticated;
grant execute on function public.delete_support_request(uuid, text) to authenticated;

create function private.archive_order_workflow(
  p_order_id uuid,
  p_restore_inventory boolean,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_order public.orders%rowtype;
  v_required record;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_inventory_restored boolean := false;
begin
  select * into v_actor from private.resolve_operational_actor(array['orders.manage']);
  if v_actor.operational_account_id is null then raise exception 'Missing orders.manage capability'; end if;
  if nullif(pg_catalog.btrim(p_reason), '') is null then raise exception 'Archive reason is required'; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order does not exist'; end if;
  if v_order.archived_at is not null then raise exception 'Order workflow is already archived'; end if;

  if p_restore_inventory and v_order.preparation_authorized_at is not null then
    if exists (
      select 1 from public.deliveries
      where order_id = p_order_id and status = 'completed' and final_result = 'delivered'
    ) then
      raise exception 'Inventory cannot be restored for a delivered order';
    end if;
    if exists (
      select 1 from public.inventory_movements
      where order_id = p_order_id and movement_kind = 'order_compensation'
    ) then
      raise exception 'Order inventory has already been restored';
    end if;

    for v_required in
      with required as (
        select item.presentation_id, item.quantity::bigint as quantity
        from public.order_items item
        where item.order_id = p_order_id and item.item_kind = 'presentation'
        union all
        select component.presentation_id, component.total_component_quantity::bigint
        from public.order_items item
        join public.order_item_package_components component on component.order_item_id = item.id
        where item.order_id = p_order_id and item.item_kind = 'package'
      )
      select required.presentation_id, pg_catalog.sum(required.quantity)::bigint as quantity
      from required
      group by required.presentation_id
      order by required.presentation_id
    loop
      update public.presentation_inventory
      set on_hand_quantity = on_hand_quantity + v_required.quantity,
          updated_at = v_now
      where presentation_id = v_required.presentation_id;
      if not found then raise exception 'Inventory row does not exist for presentation %', v_required.presentation_id; end if;

      insert into public.inventory_movements (
        id, presentation_id, quantity_delta, movement_kind,
        order_id, actor_operational_person_id, cause, occurred_at
      ) values (
        pg_catalog.gen_random_uuid(), v_required.presentation_id,
        v_required.quantity, 'order_compensation', p_order_id,
        v_actor.operational_person_id,
        'Reintegro al retirar flujo operativo: ' || pg_catalog.btrim(p_reason), v_now
      );
    end loop;
    v_inventory_restored := true;
  end if;

  update public.orders
  set archived_at = v_now,
      archive_reason = pg_catalog.btrim(p_reason),
      inventory_restored_at = case when v_inventory_restored then v_now else null end,
      updated_at = v_now
  where id = p_order_id;

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id, cause,
    previous_values, new_values
  ) values (
    pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
    v_actor.operational_account_id, v_actor.capability_id,
    'order.workflow_archived', 'order', 'orders', p_order_id,
    pg_catalog.btrim(p_reason),
    pg_catalog.jsonb_build_object('archived_at', null),
    pg_catalog.jsonb_build_object(
      'archived_at', v_now,
      'inventory_restored', v_inventory_restored,
      'restore_inventory_requested', p_restore_inventory
    )
  );

  return pg_catalog.jsonb_build_object(
    'order_id', p_order_id,
    'archived_at', v_now,
    'inventory_restored', v_inventory_restored
  );
end;
$$;

revoke all on function private.archive_order_workflow(uuid, boolean, text) from PUBLIC;
revoke all on function private.archive_order_workflow(uuid, boolean, text) from anon;
revoke all on function private.archive_order_workflow(uuid, boolean, text) from authenticated;
grant execute on function private.archive_order_workflow(uuid, boolean, text) to authenticated;

create function public.archive_order_workflow(
  p_order_id uuid,
  p_restore_inventory boolean,
  p_reason text
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.archive_order_workflow(p_order_id, p_restore_inventory, p_reason)
$$;

revoke all on function public.archive_order_workflow(uuid, boolean, text) from PUBLIC;
revoke all on function public.archive_order_workflow(uuid, boolean, text) from anon;
revoke all on function public.archive_order_workflow(uuid, boolean, text) from authenticated;
grant execute on function public.archive_order_workflow(uuid, boolean, text) to authenticated;
