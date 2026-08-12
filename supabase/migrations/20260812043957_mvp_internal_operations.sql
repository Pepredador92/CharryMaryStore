alter table public.order_actions
  drop constraint ck_order_actions__action_kind;

alter table public.order_actions
  add constraint ck_order_actions__action_kind check (
    action_kind in (
      'confirmed',
      'cancelled',
      'preparation_authorized',
      'delivery_authorized'
    )
  );

create index ix_orders__commercial_status_placed_at
  on public.orders (commercial_status, placed_at desc);

create index ix_preparations__status_created_at
  on public.preparations (status, created_at desc);

create index ix_deliveries__status_recognized_at
  on public.deliveries (status, recognized_at desc);

create index ix_support_requests__status_opened_at
  on public.support_requests (status, opened_at desc)
  where deleted_at is null;

create function private.resolve_operational_actor(p_capability_codes text[])
returns table (
  operational_account_id uuid,
  operational_person_id uuid,
  capability_id uuid,
  capability_code text
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select
    public.operational_accounts.id,
    public.operational_people.id,
    public.capabilities.id,
    public.capabilities.code
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
    and public.operational_account_capabilities.revoked_at is null
    and public.capabilities.is_active = true
    and public.capabilities.code = any (p_capability_codes)
  order by pg_catalog.array_position(p_capability_codes, public.capabilities.code)
  limit 1
$$;

revoke all on function private.resolve_operational_actor(text[]) from PUBLIC;
revoke all on function private.resolve_operational_actor(text[]) from anon;
revoke all on function private.resolve_operational_actor(text[]) from authenticated;

create function private.admin_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select pg_catalog.jsonb_build_object(
    'orders_pending', case when private.has_capability('orders.read') or private.has_capability('orders.manage')
      then (select pg_catalog.count(*) from public.orders where commercial_status = 'pending_confirmation') else null end,
    'orders_confirmed', case when private.has_capability('orders.read') or private.has_capability('orders.manage')
      then (select pg_catalog.count(*) from public.orders where commercial_status = 'confirmed') else null end,
    'preparations_pending', case when private.has_capability('preparation.read') or private.has_capability('preparation.manage') or private.has_capability('preparation.operate')
      then (select pg_catalog.count(*) from public.preparations where status = 'pending') else null end,
    'preparations_in_progress', case when private.has_capability('preparation.read') or private.has_capability('preparation.manage') or private.has_capability('preparation.operate')
      then (select pg_catalog.count(*) from public.preparations where status in ('in_progress', 'reopened')) else null end,
    'preparations_blocked', case when private.has_capability('preparation.read') or private.has_capability('preparation.manage') or private.has_capability('preparation.operate')
      then (select pg_catalog.count(*) from public.preparations where status = 'blocked') else null end,
    'deliveries_pending', case when private.has_capability('delivery.read') or private.has_capability('delivery.manage') or private.has_capability('delivery.operate')
      then (select pg_catalog.count(*) from public.deliveries where status = 'pending') else null end,
    'deliveries_active', case when private.has_capability('delivery.read') or private.has_capability('delivery.manage') or private.has_capability('delivery.operate')
      then (select pg_catalog.count(*) from public.deliveries where status in ('in_custody', 'in_transit', 'blocked', 'reopened')) else null end,
    'support_open', case when private.has_capability('support.handle')
      then (select pg_catalog.count(*) from public.support_requests where status in ('open', 'in_attention', 'channelled') and deleted_at is null) else null end,
    'low_inventory', case when private.has_capability('inventory.read') or private.has_capability('inventory.adjust')
      then (select pg_catalog.count(*) from public.presentation_inventory where on_hand_quantity <= 5) else null end
  )
  where private.current_operational_account_id() is not null
$$;

revoke all on function private.admin_dashboard() from PUBLIC;
revoke all on function private.admin_dashboard() from anon;
revoke all on function private.admin_dashboard() from authenticated;
grant execute on function private.admin_dashboard() to authenticated;

create function public.admin_dashboard()
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select private.admin_dashboard()
$$;

revoke all on function public.admin_dashboard() from PUBLIC;
revoke all on function public.admin_dashboard() from anon;
revoke all on function public.admin_dashboard() from authenticated;
grant execute on function public.admin_dashboard() to authenticated;

create function private.admin_order_detail(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_result jsonb;
begin
  if not (private.has_capability('orders.read') or private.has_capability('orders.manage')) then
    raise exception 'Missing orders.read or orders.manage capability';
  end if;

  select pg_catalog.jsonb_build_object(
    'order', pg_catalog.to_jsonb(order_row),
    'customer', pg_catalog.jsonb_build_object(
      'preferred_name', public.customers.preferred_name,
      'contact_email', public.customers.contact_email,
      'contact_phone', public.customers.contact_phone
    ),
    'destination', (
      select pg_catalog.to_jsonb(destination)
      from public.order_destinations as destination
      where destination.order_id = order_row.id and destination.is_current
      limit 1
    ),
    'items', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(item) || pg_catalog.jsonb_build_object(
          'components', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(component) order by component.historical_sku)
            from public.order_item_package_components as component
            where component.order_item_id = item.id
          ), '[]'::jsonb)
        ) order by item.line_number
      )
      from public.order_items as item
      where item.order_id = order_row.id
    ), '[]'::jsonb),
    'actions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(action) order by action.occurred_at)
      from public.order_actions as action
      where action.order_id = order_row.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.orders order_row
  join public.customers on public.customers.id = order_row.customer_id
  where order_row.id = p_order_id;

  if v_result is null then
    raise exception 'Order does not exist';
  end if;

  return v_result;
end;
$$;

revoke all on function private.admin_order_detail(uuid) from PUBLIC;
revoke all on function private.admin_order_detail(uuid) from anon;
revoke all on function private.admin_order_detail(uuid) from authenticated;
grant execute on function private.admin_order_detail(uuid) to authenticated;

create function public.admin_order_detail(p_order_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select private.admin_order_detail(p_order_id)
$$;

revoke all on function public.admin_order_detail(uuid) from PUBLIC;
revoke all on function public.admin_order_detail(uuid) from anon;
revoke all on function public.admin_order_detail(uuid) from authenticated;
grant execute on function public.admin_order_detail(uuid) to authenticated;

create function private.manage_order(
  p_order_id uuid,
  p_action text,
  p_cause text default null
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
  v_now timestamptz := pg_catalog.now();
  v_previous jsonb;
begin
  select * into v_actor
  from private.resolve_operational_actor(array['orders.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing orders.manage capability';
  end if;

  if p_action not in ('confirm', 'cancel') then
    raise exception 'Unsupported order action';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order does not exist';
  end if;

  v_previous := pg_catalog.jsonb_build_object('commercial_status', v_order.commercial_status);

  if p_action = 'confirm' then
    if v_order.commercial_status <> 'pending_confirmation' then
      raise exception 'Only pending orders can be confirmed';
    end if;

    update public.orders
    set commercial_status = 'confirmed', updated_at = v_now
    where id = p_order_id;
  else
    if v_order.commercial_status not in ('pending_confirmation', 'confirmed') then
      raise exception 'Only pending or confirmed orders can be cancelled';
    end if;

    if v_order.preparation_authorized_at is not null
      or exists (select 1 from public.preparations where order_id = p_order_id)
      or exists (select 1 from public.deliveries where order_id = p_order_id) then
      raise exception 'Order cancellation is blocked after preparation authorization';
    end if;

    if nullif(pg_catalog.btrim(p_cause), '') is null then
      raise exception 'Cancellation cause is required';
    end if;

    update public.orders
    set commercial_status = 'cancelled', updated_at = v_now
    where id = p_order_id;
  end if;

  insert into public.order_actions (
    id, order_id, action_kind, actor_operational_person_id,
    operational_account_id, capability_id, cause,
    previous_values, new_values, occurred_at
  ) values (
    pg_catalog.gen_random_uuid(), p_order_id,
    case when p_action = 'confirm' then 'confirmed' else 'cancelled' end,
    v_actor.operational_person_id, v_actor.operational_account_id,
    v_actor.capability_id, nullif(pg_catalog.btrim(p_cause), ''),
    v_previous,
    pg_catalog.jsonb_build_object('commercial_status', case when p_action = 'confirm' then 'confirmed' else 'cancelled' end),
    v_now
  );

  return pg_catalog.jsonb_build_object(
    'order_id', p_order_id,
    'commercial_status', case when p_action = 'confirm' then 'confirmed' else 'cancelled' end
  );
end;
$$;

revoke all on function private.manage_order(uuid, text, text) from PUBLIC;
revoke all on function private.manage_order(uuid, text, text) from anon;
revoke all on function private.manage_order(uuid, text, text) from authenticated;
grant execute on function private.manage_order(uuid, text, text) to authenticated;

create function public.manage_order(
  p_order_id uuid,
  p_action text,
  p_cause text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.manage_order(p_order_id, p_action, p_cause)
$$;

revoke all on function public.manage_order(uuid, text, text) from PUBLIC;
revoke all on function public.manage_order(uuid, text, text) from anon;
revoke all on function public.manage_order(uuid, text, text) from authenticated;
grant execute on function public.manage_order(uuid, text, text) to authenticated;

create function private.authorize_order_preparation(p_order_id uuid)
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
  v_preparation_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.now();
begin
  select * into v_actor
  from private.resolve_operational_actor(array['orders.manage']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing orders.manage capability';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order does not exist';
  end if;

  if v_order.commercial_status <> 'confirmed' then
    raise exception 'Order must be confirmed before preparation';
  end if;

  if v_order.preparation_authorized_at is not null
    or exists (select 1 from public.preparations where order_id = p_order_id) then
    raise exception 'Preparation has already been authorized';
  end if;

  if not exists (select 1 from public.order_items where order_id = p_order_id) then
    raise exception 'Order has no items';
  end if;

  if exists (
    select 1
    from public.order_items item
    where item.order_id = p_order_id
      and item.item_kind = 'package'
      and not exists (
        select 1 from public.order_item_package_components component
        where component.order_item_id = item.id
      )
  ) then
    raise exception 'Package snapshot is incomplete';
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
    if v_required.presentation_id is null then
      raise exception 'Historical component is not linked to a presentation';
    end if;

    perform 1
    from public.presentation_inventory
    where presentation_id = v_required.presentation_id
    for update;

    if not found or (
      select on_hand_quantity from public.presentation_inventory
      where presentation_id = v_required.presentation_id
    ) < v_required.quantity then
      raise exception 'Insufficient inventory for presentation %', v_required.presentation_id;
    end if;
  end loop;

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
    set on_hand_quantity = on_hand_quantity - v_required.quantity,
        updated_at = v_now
    where presentation_id = v_required.presentation_id;

    insert into public.inventory_movements (
      id, presentation_id, quantity_delta, movement_kind,
      order_id, actor_operational_person_id, cause, occurred_at
    ) values (
      pg_catalog.gen_random_uuid(), v_required.presentation_id,
      -v_required.quantity, 'order_decrement', p_order_id,
      v_actor.operational_person_id,
      'Autorización transaccional de preparación', v_now
    );
  end loop;

  update public.orders
  set preparation_authorized_at = v_now, updated_at = v_now
  where id = p_order_id;

  insert into public.order_actions (
    id, order_id, action_kind, actor_operational_person_id,
    operational_account_id, capability_id, cause,
    previous_values, new_values, occurred_at
  ) values (
    pg_catalog.gen_random_uuid(), p_order_id, 'preparation_authorized',
    v_actor.operational_person_id, v_actor.operational_account_id,
    v_actor.capability_id, 'Inventario revalidado y descontado',
    pg_catalog.jsonb_build_object('preparation_authorized_at', null),
    pg_catalog.jsonb_build_object('preparation_authorized_at', v_now), v_now
  );

  insert into public.preparations (id, order_id, status)
  values (v_preparation_id, p_order_id, 'pending');

  insert into public.preparation_item_verifications (
    id, preparation_id, order_item_id, verification_status, verified_quantity
  )
  select pg_catalog.gen_random_uuid(), v_preparation_id, id, 'pending', 0
  from public.order_items
  where order_id = p_order_id
  order by line_number;

  return pg_catalog.jsonb_build_object(
    'order_id', p_order_id,
    'preparation_id', v_preparation_id,
    'authorized_at', v_now
  );
end;
$$;

revoke all on function private.authorize_order_preparation(uuid) from PUBLIC;
revoke all on function private.authorize_order_preparation(uuid) from anon;
revoke all on function private.authorize_order_preparation(uuid) from authenticated;
grant execute on function private.authorize_order_preparation(uuid) to authenticated;

create function public.authorize_order_preparation(p_order_id uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.authorize_order_preparation(p_order_id)
$$;

revoke all on function public.authorize_order_preparation(uuid) from PUBLIC;
revoke all on function public.authorize_order_preparation(uuid) from anon;
revoke all on function public.authorize_order_preparation(uuid) from authenticated;
grant execute on function public.authorize_order_preparation(uuid) to authenticated;

create function private.admin_preparation_detail(p_preparation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_result jsonb;
  v_person_id uuid := private.current_operational_person_id();
begin
  if not (
    private.has_capability('preparation.read')
    or private.has_capability('preparation.manage')
    or private.has_capability('preparation.operate')
  ) then
    raise exception 'Missing preparation capability';
  end if;

  select pg_catalog.jsonb_build_object(
    'preparation', pg_catalog.to_jsonb(preparation),
    'order', pg_catalog.to_jsonb(order_row),
    'items', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(item)
        || pg_catalog.jsonb_build_object(
          'verification', pg_catalog.to_jsonb(verification),
          'components', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(component) order by component.historical_sku)
            from public.order_item_package_components component
            where component.order_item_id = item.id
          ), '[]'::jsonb)
        ) order by item.line_number
      )
      from public.order_items item
      left join public.preparation_item_verifications verification
        on verification.preparation_id = preparation.id
       and verification.order_item_id = item.id
      where item.order_id = preparation.order_id
    ), '[]'::jsonb),
    'actions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(action) order by action.occurred_at)
      from public.preparation_actions action
      where action.preparation_id = preparation.id
    ), '[]'::jsonb)
  ) into v_result
  from public.preparations preparation
  join public.orders order_row on order_row.id = preparation.order_id
  where preparation.id = p_preparation_id
    and (
      private.has_capability('preparation.read')
      or private.has_capability('preparation.manage')
      or preparation.current_responsible_person_id = v_person_id
      or preparation.current_responsible_person_id is null
    );

  if v_result is null then
    raise exception 'Preparation does not exist or is not assigned to this operator';
  end if;

  return v_result;
end;
$$;

revoke all on function private.admin_preparation_detail(uuid) from PUBLIC;
revoke all on function private.admin_preparation_detail(uuid) from anon;
revoke all on function private.admin_preparation_detail(uuid) from authenticated;
grant execute on function private.admin_preparation_detail(uuid) to authenticated;

create function public.admin_preparation_detail(p_preparation_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select private.admin_preparation_detail(p_preparation_id)
$$;

revoke all on function public.admin_preparation_detail(uuid) from PUBLIC;
revoke all on function public.admin_preparation_detail(uuid) from anon;
revoke all on function public.admin_preparation_detail(uuid) from authenticated;
grant execute on function public.admin_preparation_detail(uuid) to authenticated;

create function private.manage_preparation(
  p_preparation_id uuid,
  p_action text,
  p_order_item_id uuid default null,
  p_cause text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_preparation public.preparations%rowtype;
  v_item public.order_items%rowtype;
  v_verification public.preparation_item_verifications%rowtype;
  v_action_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_result text;
begin
  select * into v_actor
  from private.resolve_operational_actor(array['preparation.manage', 'preparation.operate']);

  if v_actor.operational_account_id is null then
    raise exception 'Missing preparation capability';
  end if;

  select * into v_preparation
  from public.preparations
  where id = p_preparation_id
  for update;

  if not found then
    raise exception 'Preparation does not exist';
  end if;

  if v_actor.capability_code = 'preparation.operate'
    and v_preparation.current_responsible_person_id is not null
    and v_preparation.current_responsible_person_id <> v_actor.operational_person_id then
    raise exception 'Preparation is assigned to another operator';
  end if;

  if p_action in ('block', 'end_incomplete')
    and nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'Cause is required';
  end if;

  if p_action = 'start' then
    if v_preparation.status not in ('pending', 'reopened') then
      raise exception 'Preparation cannot be started from its current state';
    end if;
    update public.preparations
    set status = 'in_progress',
        current_responsible_person_id = coalesce(current_responsible_person_id, v_actor.operational_person_id),
        started_at = coalesce(started_at, v_now),
        reopened_at = case when status = 'reopened' then reopened_at else null end,
        updated_at = v_now
    where id = p_preparation_id;
    v_result := 'in_progress';
  elsif p_action in ('verify', 'invalidate') then
    if v_preparation.status not in ('in_progress', 'reopened') then
      raise exception 'Items can only be handled during an active preparation';
    end if;

    select * into v_item
    from public.order_items
    where id = p_order_item_id and order_id = v_preparation.order_id;

    if not found then
      raise exception 'Order item does not belong to this preparation';
    end if;

    select * into v_verification
    from public.preparation_item_verifications
    where preparation_id = p_preparation_id and order_item_id = p_order_item_id
    for update;

    if not found then
      raise exception 'Verification row does not exist';
    end if;

    if p_action = 'verify' then
      if v_verification.verification_status = 'verified' then
        raise exception 'Item is already verified';
      end if;
      update public.preparation_item_verifications
      set verification_status = 'verified',
          verified_quantity = v_item.quantity,
          verified_by_person_id = v_actor.operational_person_id,
          verified_at = v_now,
          invalidated_at = null,
          updated_at = v_now
      where id = v_verification.id;
      v_result := 'verified';
    else
      if v_verification.verification_status <> 'verified' then
        raise exception 'Only a verified item can be invalidated';
      end if;
      if nullif(pg_catalog.btrim(p_cause), '') is null then
        raise exception 'Invalidation cause is required';
      end if;
      update public.preparation_item_verifications
      set verification_status = 'invalidated',
          invalidated_at = v_now,
          updated_at = v_now
      where id = v_verification.id;
      v_result := 'invalidated';
    end if;
  elsif p_action = 'block' then
    if v_preparation.status not in ('pending', 'in_progress', 'reopened') then
      raise exception 'Preparation cannot be blocked from its current state';
    end if;
    update public.preparations
    set status = 'blocked', blocked_at = v_now,
        current_block_reason = pg_catalog.btrim(p_cause), updated_at = v_now
    where id = p_preparation_id;
    v_result := 'blocked';
  elsif p_action = 'unblock' then
    if v_preparation.status <> 'blocked' then
      raise exception 'Only blocked preparations can be unblocked';
    end if;
    update public.preparations
    set status = 'in_progress', blocked_at = null, current_block_reason = null,
        current_responsible_person_id = coalesce(current_responsible_person_id, v_actor.operational_person_id),
        started_at = coalesce(started_at, v_now), updated_at = v_now
    where id = p_preparation_id;
    v_result := 'in_progress';
  elsif p_action = 'complete' then
    if v_preparation.status not in ('in_progress', 'reopened') then
      raise exception 'Preparation cannot be completed from its current state';
    end if;
    if exists (
      select 1 from public.preparation_item_verifications
      where preparation_id = p_preparation_id and verification_status <> 'verified'
    ) or not exists (
      select 1 from public.preparation_item_verifications
      where preparation_id = p_preparation_id
    ) then
      raise exception 'Every order item must be verified before completion';
    end if;
    update public.preparations
    set status = 'completed', completed_at = v_now,
        terminated_at = null, blocked_at = null, current_block_reason = null,
        updated_at = v_now
    where id = p_preparation_id;
    v_result := 'completed';
  elsif p_action = 'end_incomplete' then
    if v_preparation.status not in ('pending', 'in_progress', 'blocked', 'reopened') then
      raise exception 'Preparation cannot end incomplete from its current state';
    end if;
    update public.preparations
    set status = 'ended_incomplete', terminated_at = v_now,
        completed_at = null, blocked_at = null, current_block_reason = null,
        updated_at = v_now
    where id = p_preparation_id;
    v_result := 'ended_incomplete';
  elsif p_action = 'reopen' then
    if v_preparation.status not in ('completed', 'ended_incomplete') then
      raise exception 'Only finalized preparations can be reopened';
    end if;
    if v_actor.capability_code <> 'preparation.manage' then
      raise exception 'Reopening requires preparation.manage';
    end if;
    update public.preparations
    set status = 'reopened', reopened_at = v_now,
        completed_at = null, terminated_at = null,
        current_responsible_person_id = v_actor.operational_person_id,
        updated_at = v_now
    where id = p_preparation_id;
    v_result := 'reopened';
  else
    raise exception 'Unsupported preparation action';
  end if;

  insert into public.preparation_actions (
    id, preparation_id, order_item_id, action_kind,
    actor_operational_person_id, operational_account_id, capability_id,
    result, cause, details, occurred_at
  ) values (
    v_action_id, p_preparation_id, p_order_item_id, p_action,
    v_actor.operational_person_id, v_actor.operational_account_id, v_actor.capability_id,
    v_result, nullif(pg_catalog.btrim(p_cause), ''),
    pg_catalog.jsonb_build_object('previous_status', v_preparation.status), v_now
  );

  if p_action in ('verify', 'invalidate') then
    update public.preparation_item_verifications
    set last_action_id = v_action_id, updated_at = v_now
    where preparation_id = p_preparation_id and order_item_id = p_order_item_id;
  end if;

  return pg_catalog.jsonb_build_object(
    'preparation_id', p_preparation_id,
    'status', case when p_action in ('verify', 'invalidate') then v_preparation.status else v_result end,
    'item_status', case when p_action in ('verify', 'invalidate') then v_result else null end
  );
end;
$$;

revoke all on function private.manage_preparation(uuid, text, uuid, text) from PUBLIC;
revoke all on function private.manage_preparation(uuid, text, uuid, text) from anon;
revoke all on function private.manage_preparation(uuid, text, uuid, text) from authenticated;
grant execute on function private.manage_preparation(uuid, text, uuid, text) to authenticated;

create function public.manage_preparation(
  p_preparation_id uuid,
  p_action text,
  p_order_item_id uuid default null,
  p_cause text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.manage_preparation(p_preparation_id, p_action, p_order_item_id, p_cause)
$$;

revoke all on function public.manage_preparation(uuid, text, uuid, text) from PUBLIC;
revoke all on function public.manage_preparation(uuid, text, uuid, text) from anon;
revoke all on function public.manage_preparation(uuid, text, uuid, text) from authenticated;
grant execute on function public.manage_preparation(uuid, text, uuid, text) to authenticated;

create function private.create_order_delivery(p_order_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_order public.orders%rowtype;
  v_preparation public.preparations%rowtype;
  v_delivery_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor
  from private.resolve_operational_actor(array['delivery.manage']);
  if v_actor.operational_account_id is null then
    raise exception 'Missing delivery.manage capability';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order does not exist'; end if;
  if v_order.commercial_status <> 'confirmed' then
    raise exception 'Only confirmed orders can enter delivery';
  end if;

  select * into v_preparation
  from public.preparations
  where order_id = p_order_id
  for update;
  if not found or v_preparation.status <> 'completed' then
    raise exception 'Preparation must be completed before delivery';
  end if;
  if exists (select 1 from public.deliveries where order_id = p_order_id) then
    raise exception 'Delivery already exists for this order';
  end if;

  update public.orders
  set delivery_authorized_at = v_now, updated_at = v_now
  where id = p_order_id;

  insert into public.order_actions (
    id, order_id, action_kind, actor_operational_person_id,
    operational_account_id, capability_id, cause,
    previous_values, new_values, occurred_at
  ) values (
    pg_catalog.gen_random_uuid(), p_order_id, 'delivery_authorized',
    v_actor.operational_person_id, v_actor.operational_account_id,
    v_actor.capability_id, 'Preparación completa revalidada',
    pg_catalog.jsonb_build_object('delivery_authorized_at', null),
    pg_catalog.jsonb_build_object('delivery_authorized_at', v_now), v_now
  );

  insert into public.deliveries (id, order_id, status, recognized_at)
  values (v_delivery_id, p_order_id, 'pending', v_now);

  return pg_catalog.jsonb_build_object('delivery_id', v_delivery_id, 'order_id', p_order_id, 'status', 'pending');
end;
$$;

revoke all on function private.create_order_delivery(uuid) from PUBLIC;
revoke all on function private.create_order_delivery(uuid) from anon;
revoke all on function private.create_order_delivery(uuid) from authenticated;
grant execute on function private.create_order_delivery(uuid) to authenticated;

create function public.create_order_delivery(p_order_id uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.create_order_delivery(p_order_id)
$$;

revoke all on function public.create_order_delivery(uuid) from PUBLIC;
revoke all on function public.create_order_delivery(uuid) from anon;
revoke all on function public.create_order_delivery(uuid) from authenticated;
grant execute on function public.create_order_delivery(uuid) to authenticated;

create function private.save_logistics_provider(
  p_provider_id uuid,
  p_name text,
  p_external_reference text default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_id uuid := coalesce(p_provider_id, pg_catalog.gen_random_uuid());
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery.manage']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery.manage capability'; end if;
  if nullif(pg_catalog.btrim(p_name), '') is null then raise exception 'Provider name is required'; end if;

  insert into public.logistics_providers (id, name, external_reference, is_active)
  values (v_id, pg_catalog.btrim(p_name), nullif(pg_catalog.btrim(p_external_reference), ''), p_is_active)
  on conflict (id) do update
  set name = excluded.name,
      external_reference = excluded.external_reference,
      is_active = excluded.is_active,
      updated_at = pg_catalog.clock_timestamp();

  return v_id;
end;
$$;

revoke all on function private.save_logistics_provider(uuid, text, text, boolean) from PUBLIC;
revoke all on function private.save_logistics_provider(uuid, text, text, boolean) from anon;
revoke all on function private.save_logistics_provider(uuid, text, text, boolean) from authenticated;
grant execute on function private.save_logistics_provider(uuid, text, text, boolean) to authenticated;

create function public.save_logistics_provider(
  p_provider_id uuid,
  p_name text,
  p_external_reference text default null,
  p_is_active boolean default true
)
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.save_logistics_provider(p_provider_id, p_name, p_external_reference, p_is_active)
$$;

revoke all on function public.save_logistics_provider(uuid, text, text, boolean) from PUBLIC;
revoke all on function public.save_logistics_provider(uuid, text, text, boolean) from anon;
revoke all on function public.save_logistics_provider(uuid, text, text, boolean) from authenticated;
grant execute on function public.save_logistics_provider(uuid, text, text, boolean) to authenticated;

create function private.assign_delivery(
  p_delivery_id uuid,
  p_operational_person_id uuid default null,
  p_logistics_provider_id uuid default null,
  p_external_person_reference text default null,
  p_assignment_kind text default 'responsible',
  p_cause text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_delivery public.deliveries%rowtype;
  v_assignment_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery.manage']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery.manage capability'; end if;
  if (p_operational_person_id is null) = (p_logistics_provider_id is null) then
    raise exception 'Choose exactly one assignee';
  end if;
  if nullif(pg_catalog.btrim(p_assignment_kind), '') is null then raise exception 'Assignment kind is required'; end if;
  if nullif(pg_catalog.btrim(p_cause), '') is null then raise exception 'Assignment cause is required'; end if;

  select * into v_delivery from public.deliveries where id = p_delivery_id for update;
  if not found then raise exception 'Delivery does not exist'; end if;
  if v_delivery.status = 'completed' then raise exception 'Completed delivery cannot be reassigned'; end if;

  if p_operational_person_id is not null and not exists (
    select 1 from public.operational_people
    where id = p_operational_person_id and status = 'active' and ended_at is null
  ) then raise exception 'Operational person is not active'; end if;

  if p_logistics_provider_id is not null and not exists (
    select 1 from public.logistics_providers
    where id = p_logistics_provider_id and is_active
  ) then raise exception 'Logistics provider is not active'; end if;

  update public.delivery_assignments
  set ended_at = v_now, change_reason = pg_catalog.btrim(p_cause)
  where delivery_id = p_delivery_id and ended_at is null;

  insert into public.delivery_assignments (
    id, delivery_id, operational_person_id, logistics_provider_id,
    external_person_reference, assignment_kind, started_at, change_reason
  ) values (
    v_assignment_id, p_delivery_id, p_operational_person_id, p_logistics_provider_id,
    nullif(pg_catalog.btrim(p_external_person_reference), ''),
    pg_catalog.btrim(p_assignment_kind), v_now, pg_catalog.btrim(p_cause)
  );

  insert into public.delivery_actions (
    id, delivery_id, action_kind, actor_operational_person_id,
    operational_account_id, capability_id, cause, new_values, occurred_at
  ) values (
    pg_catalog.gen_random_uuid(), p_delivery_id, 'assignment_changed',
    v_actor.operational_person_id, v_actor.operational_account_id,
    v_actor.capability_id, pg_catalog.btrim(p_cause),
    pg_catalog.jsonb_build_object(
      'assignment_id', v_assignment_id,
      'operational_person_id', p_operational_person_id,
      'logistics_provider_id', p_logistics_provider_id
    ), v_now
  );

  return v_assignment_id;
end;
$$;

revoke all on function private.assign_delivery(uuid, uuid, uuid, text, text, text) from PUBLIC;
revoke all on function private.assign_delivery(uuid, uuid, uuid, text, text, text) from anon;
revoke all on function private.assign_delivery(uuid, uuid, uuid, text, text, text) from authenticated;
grant execute on function private.assign_delivery(uuid, uuid, uuid, text, text, text) to authenticated;

create function public.assign_delivery(
  p_delivery_id uuid,
  p_operational_person_id uuid default null,
  p_logistics_provider_id uuid default null,
  p_external_person_reference text default null,
  p_assignment_kind text default 'responsible',
  p_cause text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.assign_delivery(
    p_delivery_id, p_operational_person_id, p_logistics_provider_id,
    p_external_person_reference, p_assignment_kind, p_cause
  )
$$;

revoke all on function public.assign_delivery(uuid, uuid, uuid, text, text, text) from PUBLIC;
revoke all on function public.assign_delivery(uuid, uuid, uuid, text, text, text) from anon;
revoke all on function public.assign_delivery(uuid, uuid, uuid, text, text, text) from authenticated;
grant execute on function public.assign_delivery(uuid, uuid, uuid, text, text, text) to authenticated;

create function private.record_delivery_custody(
  p_delivery_id uuid,
  p_event_kind text,
  p_from_party_kind text,
  p_from_operational_person_id uuid default null,
  p_from_provider_id uuid default null,
  p_to_party_kind text default 'cherry_mary',
  p_to_operational_person_id uuid default null,
  p_to_provider_id uuid default null,
  p_external_party_reference text default null,
  p_cause text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_delivery public.deliveries%rowtype;
  v_event_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery.manage', 'delivery.operate']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery capability'; end if;

  select * into v_delivery from public.deliveries where id = p_delivery_id for update;
  if not found then raise exception 'Delivery does not exist'; end if;
  if v_delivery.status = 'completed' then raise exception 'Completed delivery cannot accept custody events'; end if;
  if v_actor.capability_code = 'delivery.operate' and not exists (
    select 1 from public.delivery_assignments
    where delivery_id = p_delivery_id
      and operational_person_id = v_actor.operational_person_id
      and ended_at is null
  ) then raise exception 'Delivery is not assigned to this operator'; end if;

  insert into public.delivery_custody_events (
    id, delivery_id, event_kind, from_party_kind,
    from_operational_person_id, from_provider_id,
    to_party_kind, to_operational_person_id, to_provider_id,
    external_party_reference, cause, occurred_at
  ) values (
    v_event_id, p_delivery_id, p_event_kind, p_from_party_kind,
    p_from_operational_person_id, p_from_provider_id,
    p_to_party_kind, p_to_operational_person_id, p_to_provider_id,
    nullif(pg_catalog.btrim(p_external_party_reference), ''),
    nullif(pg_catalog.btrim(p_cause), ''), v_now
  );

  if p_event_kind = 'accepted' and v_delivery.status in ('pending', 'reopened') then
    update public.deliveries
    set status = 'in_custody', custody_accepted_at = v_now, updated_at = v_now
    where id = p_delivery_id;
  end if;

  return v_event_id;
end;
$$;

revoke all on function private.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) from PUBLIC;
revoke all on function private.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) from anon;
revoke all on function private.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) from authenticated;
grant execute on function private.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) to authenticated;

create function public.record_delivery_custody(
  p_delivery_id uuid,
  p_event_kind text,
  p_from_party_kind text,
  p_from_operational_person_id uuid default null,
  p_from_provider_id uuid default null,
  p_to_party_kind text default 'cherry_mary',
  p_to_operational_person_id uuid default null,
  p_to_provider_id uuid default null,
  p_external_party_reference text default null,
  p_cause text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.record_delivery_custody(
    p_delivery_id, p_event_kind, p_from_party_kind,
    p_from_operational_person_id, p_from_provider_id,
    p_to_party_kind, p_to_operational_person_id, p_to_provider_id,
    p_external_party_reference, p_cause
  )
$$;

revoke all on function public.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) from PUBLIC;
revoke all on function public.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) from anon;
revoke all on function public.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) from authenticated;
grant execute on function public.record_delivery_custody(uuid, text, text, uuid, uuid, text, uuid, uuid, text, text) to authenticated;

create function private.set_delivery_state(
  p_delivery_id uuid,
  p_action text,
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
  v_delivery public.deliveries%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_status text;
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery.manage', 'delivery.operate']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery capability'; end if;
  if nullif(pg_catalog.btrim(p_cause), '') is null then raise exception 'Cause is required'; end if;

  select * into v_delivery from public.deliveries where id = p_delivery_id for update;
  if not found then raise exception 'Delivery does not exist'; end if;
  if v_actor.capability_code = 'delivery.operate' and not exists (
    select 1 from public.delivery_assignments
    where delivery_id = p_delivery_id
      and operational_person_id = v_actor.operational_person_id
      and ended_at is null
  ) then raise exception 'Delivery is not assigned to this operator'; end if;

  if p_action = 'start_transit' then
    if v_delivery.status not in ('in_custody', 'reopened') then raise exception 'Delivery is not ready for transit'; end if;
    update public.deliveries set status = 'in_transit', departed_at = coalesce(departed_at, v_now), updated_at = v_now where id = p_delivery_id;
    v_status := 'in_transit';
  elsif p_action = 'block' then
    if v_delivery.status not in ('pending', 'in_custody', 'in_transit', 'reopened') then raise exception 'Delivery cannot be blocked'; end if;
    update public.deliveries set status = 'blocked', updated_at = v_now where id = p_delivery_id;
    v_status := 'blocked';
  elsif p_action = 'reopen' then
    if v_delivery.status <> 'completed' then raise exception 'Only completed delivery can be reopened'; end if;
    if v_actor.capability_code <> 'delivery.manage' then raise exception 'Reopening requires delivery.manage'; end if;
    update public.deliveries
    set status = 'reopened', final_result = null, completed_at = null,
        reopened_at = v_now, updated_at = v_now
    where id = p_delivery_id;
    v_status := 'reopened';
  else
    raise exception 'Unsupported delivery action';
  end if;

  insert into public.delivery_actions (
    id, delivery_id, action_kind, actor_operational_person_id,
    operational_account_id, capability_id, cause,
    previous_values, new_values, occurred_at
  ) values (
    pg_catalog.gen_random_uuid(), p_delivery_id,
    case p_action when 'start_transit' then 'disposition_authorized' when 'block' then 'blocked' else 'reopened' end,
    v_actor.operational_person_id, v_actor.operational_account_id,
    v_actor.capability_id, pg_catalog.btrim(p_cause),
    pg_catalog.jsonb_build_object('status', v_delivery.status),
    pg_catalog.jsonb_build_object('status', v_status), v_now
  );

  return pg_catalog.jsonb_build_object('delivery_id', p_delivery_id, 'status', v_status);
end;
$$;

revoke all on function private.set_delivery_state(uuid, text, text) from PUBLIC;
revoke all on function private.set_delivery_state(uuid, text, text) from anon;
revoke all on function private.set_delivery_state(uuid, text, text) from authenticated;
grant execute on function private.set_delivery_state(uuid, text, text) to authenticated;

create function public.set_delivery_state(p_delivery_id uuid, p_action text, p_cause text)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$ select private.set_delivery_state(p_delivery_id, p_action, p_cause) $$;

revoke all on function public.set_delivery_state(uuid, text, text) from PUBLIC;
revoke all on function public.set_delivery_state(uuid, text, text) from anon;
revoke all on function public.set_delivery_state(uuid, text, text) from authenticated;
grant execute on function public.set_delivery_state(uuid, text, text) to authenticated;

create function private.register_delivery_attempt(
  p_delivery_id uuid,
  p_result text,
  p_failure_cause text default null,
  p_receipt_confirmation text default null,
  p_event_source text default 'manual_operation',
  p_started_at timestamptz default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_delivery public.deliveries%rowtype;
  v_destination public.order_destinations%rowtype;
  v_assignment public.delivery_assignments%rowtype;
  v_attempt_id uuid := pg_catalog.gen_random_uuid();
  v_attempt_number integer;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_started_at timestamptz := coalesce(p_started_at, v_now);
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery.manage', 'delivery.operate']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery capability'; end if;
  if p_result not in ('delivered', 'failed', 'rejected', 'inaccessible', 'cancelled') then
    raise exception 'Unsupported attempt result';
  end if;
  if p_result = 'delivered' and nullif(pg_catalog.btrim(p_receipt_confirmation), '') is null then
    raise exception 'Receipt confirmation is required for a delivered attempt';
  end if;
  if p_result <> 'delivered' and nullif(pg_catalog.btrim(p_failure_cause), '') is null then
    raise exception 'Failure cause is required';
  end if;
  if v_started_at > v_now then raise exception 'Attempt start cannot be in the future'; end if;

  select * into v_delivery from public.deliveries where id = p_delivery_id for update;
  if not found then raise exception 'Delivery does not exist'; end if;
  if v_delivery.status not in ('in_custody', 'in_transit', 'reopened') then
    raise exception 'Delivery is not active for attempts';
  end if;

  select * into v_assignment
  from public.delivery_assignments
  where delivery_id = p_delivery_id and ended_at is null
  order by started_at desc
  limit 1;

  if v_actor.capability_code = 'delivery.operate'
    and (not found or v_assignment.operational_person_id <> v_actor.operational_person_id) then
    raise exception 'Delivery is not assigned to this operator';
  end if;

  select * into v_destination
  from public.order_destinations
  where order_id = v_delivery.order_id and is_current
  limit 1;
  if not found then raise exception 'Current delivery destination does not exist'; end if;

  select coalesce(pg_catalog.max(attempt_number), 0) + 1
  into v_attempt_number
  from public.delivery_attempts
  where delivery_id = p_delivery_id;

  insert into public.delivery_attempts (
    id, delivery_id, attempt_number, result, failure_cause,
    operational_person_id, logistics_provider_id,
    started_at, completed_at,
    destination_line_1, destination_line_2, destination_city,
    destination_region, destination_postal_code, destination_country_code,
    recipient_name_used, receipt_confirmation, event_source
  ) values (
    v_attempt_id, p_delivery_id, v_attempt_number, p_result,
    case when p_result = 'delivered' then null else pg_catalog.btrim(p_failure_cause) end,
    case when v_assignment.id is null then v_actor.operational_person_id else v_assignment.operational_person_id end,
    case when v_assignment.id is null then null else v_assignment.logistics_provider_id end,
    v_started_at, v_now,
    v_destination.line_1, v_destination.line_2, v_destination.city,
    v_destination.region, v_destination.postal_code, v_destination.country_code,
    v_destination.recipient_name,
    case when p_result = 'delivered' then pg_catalog.btrim(p_receipt_confirmation) else null end,
    coalesce(nullif(pg_catalog.btrim(p_event_source), ''), 'manual_operation')
  );

  if p_result = 'delivered' then
    update public.deliveries
    set status = 'completed', final_result = 'delivered', completed_at = v_now, updated_at = v_now
    where id = p_delivery_id;
  elsif v_delivery.status <> 'in_transit' then
    update public.deliveries set status = 'in_transit', updated_at = v_now where id = p_delivery_id;
  end if;

  insert into public.delivery_actions (
    id, delivery_id, attempt_id, action_kind,
    actor_operational_person_id, operational_account_id, capability_id,
    cause, new_values, occurred_at
  ) values (
    pg_catalog.gen_random_uuid(), p_delivery_id, v_attempt_id,
    case when p_result = 'delivered' then 'completed' else 'rescheduled' end,
    v_actor.operational_person_id, v_actor.operational_account_id, v_actor.capability_id,
    case when p_result = 'delivered' then 'Entrega confirmada' else pg_catalog.btrim(p_failure_cause) end,
    pg_catalog.jsonb_build_object('attempt_number', v_attempt_number, 'result', p_result), v_now
  );

  return pg_catalog.jsonb_build_object(
    'delivery_id', p_delivery_id,
    'attempt_id', v_attempt_id,
    'attempt_number', v_attempt_number,
    'result', p_result,
    'delivery_status', case when p_result = 'delivered' then 'completed' else 'in_transit' end
  );
end;
$$;

revoke all on function private.register_delivery_attempt(uuid, text, text, text, text, timestamptz) from PUBLIC;
revoke all on function private.register_delivery_attempt(uuid, text, text, text, text, timestamptz) from anon;
revoke all on function private.register_delivery_attempt(uuid, text, text, text, text, timestamptz) from authenticated;
grant execute on function private.register_delivery_attempt(uuid, text, text, text, text, timestamptz) to authenticated;

create function public.register_delivery_attempt(
  p_delivery_id uuid,
  p_result text,
  p_failure_cause text default null,
  p_receipt_confirmation text default null,
  p_event_source text default 'manual_operation',
  p_started_at timestamptz default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.register_delivery_attempt(
    p_delivery_id, p_result, p_failure_cause,
    p_receipt_confirmation, p_event_source, p_started_at
  )
$$;

revoke all on function public.register_delivery_attempt(uuid, text, text, text, text, timestamptz) from PUBLIC;
revoke all on function public.register_delivery_attempt(uuid, text, text, text, text, timestamptz) from anon;
revoke all on function public.register_delivery_attempt(uuid, text, text, text, text, timestamptz) from authenticated;
grant execute on function public.register_delivery_attempt(uuid, text, text, text, text, timestamptz) to authenticated;

create function private.admin_delivery_detail(p_delivery_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_person_id uuid := private.current_operational_person_id();
  v_result jsonb;
begin
  if not (
    private.has_capability('delivery.read')
    or private.has_capability('delivery.manage')
    or private.has_capability('delivery.operate')
  ) then raise exception 'Missing delivery capability'; end if;

  select pg_catalog.jsonb_build_object(
    'delivery', pg_catalog.to_jsonb(delivery),
    'order', pg_catalog.to_jsonb(order_row),
    'destination', (
      select pg_catalog.to_jsonb(destination)
      from public.order_destinations destination
      where destination.order_id = order_row.id and destination.is_current
      limit 1
    ),
    'assignments', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(assignment) || pg_catalog.jsonb_build_object(
          'person_name', person.display_name,
          'provider_name', provider.name
        ) order by assignment.started_at
      )
      from public.delivery_assignments assignment
      left join public.operational_people person on person.id = assignment.operational_person_id
      left join public.logistics_providers provider on provider.id = assignment.logistics_provider_id
      where assignment.delivery_id = delivery.id
    ), '[]'::jsonb),
    'custody_events', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(event) order by event.occurred_at)
      from public.delivery_custody_events event where event.delivery_id = delivery.id
    ), '[]'::jsonb),
    'attempts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(attempt) order by attempt.attempt_number)
      from public.delivery_attempts attempt where attempt.delivery_id = delivery.id
    ), '[]'::jsonb),
    'actions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(action) order by action.occurred_at)
      from public.delivery_actions action where action.delivery_id = delivery.id
    ), '[]'::jsonb)
  ) into v_result
  from public.deliveries delivery
  join public.orders order_row on order_row.id = delivery.order_id
  where delivery.id = p_delivery_id
    and (
      private.has_capability('delivery.read')
      or private.has_capability('delivery.manage')
      or exists (
        select 1 from public.delivery_assignments assignment
        where assignment.delivery_id = delivery.id
          and assignment.operational_person_id = v_actor_person_id
          and assignment.ended_at is null
      )
    );

  if v_result is null then raise exception 'Delivery does not exist or is not assigned to this operator'; end if;
  return v_result;
end;
$$;

revoke all on function private.admin_delivery_detail(uuid) from PUBLIC;
revoke all on function private.admin_delivery_detail(uuid) from anon;
revoke all on function private.admin_delivery_detail(uuid) from authenticated;
grant execute on function private.admin_delivery_detail(uuid) to authenticated;

create function public.admin_delivery_detail(p_delivery_id uuid)
returns jsonb language sql stable security invoker set search_path = pg_catalog
as $$ select private.admin_delivery_detail(p_delivery_id) $$;

revoke all on function public.admin_delivery_detail(uuid) from PUBLIC;
revoke all on function public.admin_delivery_detail(uuid) from anon;
revoke all on function public.admin_delivery_detail(uuid) from authenticated;
grant execute on function public.admin_delivery_detail(uuid) to authenticated;

create function private.delivery_assignment_options()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select pg_catalog.jsonb_build_object(
    'people', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('id', person.id, 'display_name', person.display_name)
        order by person.display_name
      )
      from public.operational_people person
      where person.status = 'active' and person.ended_at is null
    ), '[]'::jsonb),
    'providers', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('id', provider.id, 'name', provider.name)
        order by provider.name
      )
      from public.logistics_providers provider
      where provider.is_active
    ), '[]'::jsonb)
  )
  where private.has_capability('delivery.manage')
$$;

revoke all on function private.delivery_assignment_options() from PUBLIC;
revoke all on function private.delivery_assignment_options() from anon;
revoke all on function private.delivery_assignment_options() from authenticated;
grant execute on function private.delivery_assignment_options() to authenticated;

create function public.delivery_assignment_options()
returns jsonb language sql stable security invoker set search_path = pg_catalog
as $$ select private.delivery_assignment_options() $$;

revoke all on function public.delivery_assignment_options() from PUBLIC;
revoke all on function public.delivery_assignment_options() from anon;
revoke all on function public.delivery_assignment_options() from authenticated;
grant execute on function public.delivery_assignment_options() to authenticated;

create function private.list_delivery_evidence(p_delivery_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_result jsonb;
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery_evidence.read', 'delivery_evidence.manage']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery evidence capability'; end if;
  if not exists (select 1 from public.deliveries where id = p_delivery_id) then raise exception 'Delivery does not exist'; end if;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(item) order by item.created_at), '[]'::jsonb)
  into v_result
  from public.delivery_evidence_items item
  where item.delivery_id = p_delivery_id;

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id, cause
  ) values (
    pg_catalog.gen_random_uuid(), pg_catalog.clock_timestamp(),
    v_actor.operational_person_id, v_actor.operational_account_id, v_actor.capability_id,
    'delivery_evidence.viewed', 'delivery', 'deliveries', p_delivery_id,
    'Acceso operativo a metadatos de evidencia restringida'
  );

  return v_result;
end;
$$;

revoke all on function private.list_delivery_evidence(uuid) from PUBLIC;
revoke all on function private.list_delivery_evidence(uuid) from anon;
revoke all on function private.list_delivery_evidence(uuid) from authenticated;
grant execute on function private.list_delivery_evidence(uuid) to authenticated;

create function public.list_delivery_evidence(p_delivery_id uuid)
returns jsonb language sql volatile security invoker set search_path = pg_catalog
as $$ select private.list_delivery_evidence(p_delivery_id) $$;

revoke all on function public.list_delivery_evidence(uuid) from PUBLIC;
revoke all on function public.list_delivery_evidence(uuid) from anon;
revoke all on function public.list_delivery_evidence(uuid) from authenticated;
grant execute on function public.list_delivery_evidence(uuid) to authenticated;

create function private.register_delivery_evidence(
  p_delivery_id uuid,
  p_delivery_attempt_id uuid,
  p_purpose text,
  p_evidence_kind text,
  p_retention_class text,
  p_dispute_context text,
  p_exceptional_obligation_reference text,
  p_content_reference text,
  p_content_mime_type text,
  p_is_sensitive boolean,
  p_retention_due_at timestamptz,
  p_review_at timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_delivery public.deliveries%rowtype;
  v_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery_evidence.manage']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery_evidence.manage capability'; end if;
  if nullif(pg_catalog.btrim(p_purpose), '') is null then raise exception 'Evidence purpose is required'; end if;
  if nullif(pg_catalog.btrim(p_evidence_kind), '') is null then raise exception 'Evidence kind is required'; end if;
  if p_retention_due_at is null then raise exception 'Retention due date is required'; end if;
  if p_retention_due_at < v_now then raise exception 'Retention due date cannot be in the past'; end if;

  select * into v_delivery from public.deliveries where id = p_delivery_id;
  if not found then raise exception 'Delivery does not exist'; end if;
  if p_delivery_attempt_id is not null and not exists (
    select 1 from public.delivery_attempts where delivery_id = p_delivery_id and id = p_delivery_attempt_id
  ) then raise exception 'Attempt does not belong to this delivery'; end if;

  if p_retention_class = 'sensitive_no_dispute' then
    if v_delivery.status <> 'completed' or v_delivery.completed_at is null then
      raise exception 'Completed delivery is required for no-dispute evidence';
    end if;
    if p_retention_due_at > v_delivery.completed_at + interval '14 days' then
      raise exception 'No-dispute evidence cannot be retained beyond 14 days after delivery completion';
    end if;
    if p_dispute_context is not null or p_exceptional_obligation_reference is not null or p_review_at is not null then
      raise exception 'No-dispute evidence cannot include dispute or exception metadata';
    end if;
  elsif p_retention_class = 'dispute_evidence' then
    if nullif(pg_catalog.btrim(p_dispute_context), '') is null then raise exception 'Dispute context is required'; end if;
    if p_retention_due_at > v_now + interval '90 days' then
      raise exception 'Dispute evidence due date cannot exceed the approved 90-day window';
    end if;
  elsif p_retention_class = 'exceptional_obligation' then
    if nullif(pg_catalog.btrim(p_exceptional_obligation_reference), '') is null or p_review_at is null then
      raise exception 'Documented obligation and review date are required';
    end if;
  else
    raise exception 'Unsupported retention class';
  end if;

  insert into public.delivery_evidence_items (
    id, delivery_id, delivery_attempt_id, purpose, evidence_kind,
    retention_class, dispute_context, exceptional_obligation_reference,
    content_reference, content_mime_type, is_sensitive,
    retention_due_at, review_at
  ) values (
    v_id, p_delivery_id, p_delivery_attempt_id,
    pg_catalog.btrim(p_purpose), pg_catalog.btrim(p_evidence_kind), p_retention_class,
    nullif(pg_catalog.btrim(p_dispute_context), ''),
    nullif(pg_catalog.btrim(p_exceptional_obligation_reference), ''),
    nullif(pg_catalog.btrim(p_content_reference), ''),
    nullif(pg_catalog.btrim(p_content_mime_type), ''),
    p_is_sensitive, p_retention_due_at, p_review_at
  );

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id, cause,
    new_values
  ) values (
    pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
    v_actor.operational_account_id, v_actor.capability_id,
    'delivery_evidence.registered', 'delivery', 'delivery_evidence_items', v_id,
    'Registro de metadatos de evidencia',
    pg_catalog.jsonb_build_object('delivery_id', p_delivery_id, 'retention_class', p_retention_class)
  );

  return v_id;
end;
$$;

revoke all on function private.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) from PUBLIC;
revoke all on function private.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) from anon;
revoke all on function private.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) from authenticated;
grant execute on function private.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) to authenticated;

create function public.register_delivery_evidence(
  p_delivery_id uuid,
  p_delivery_attempt_id uuid,
  p_purpose text,
  p_evidence_kind text,
  p_retention_class text,
  p_dispute_context text,
  p_exceptional_obligation_reference text,
  p_content_reference text,
  p_content_mime_type text,
  p_is_sensitive boolean,
  p_retention_due_at timestamptz,
  p_review_at timestamptz
)
returns uuid language sql volatile security invoker set search_path = pg_catalog
as $$
  select private.register_delivery_evidence(
    p_delivery_id, p_delivery_attempt_id, p_purpose, p_evidence_kind,
    p_retention_class, p_dispute_context, p_exceptional_obligation_reference,
    p_content_reference, p_content_mime_type, p_is_sensitive,
    p_retention_due_at, p_review_at
  )
$$;

revoke all on function public.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) from PUBLIC;
revoke all on function public.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) from anon;
revoke all on function public.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) from authenticated;
grant execute on function public.register_delivery_evidence(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, timestamptz) to authenticated;

create function private.delete_delivery_evidence(p_evidence_id uuid, p_reason text)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor record;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor from private.resolve_operational_actor(array['delivery_evidence.manage']);
  if v_actor.operational_account_id is null then raise exception 'Missing delivery_evidence.manage capability'; end if;
  if nullif(pg_catalog.btrim(p_reason), '') is null then raise exception 'Deletion reason is required'; end if;

  update public.delivery_evidence_items
  set deleted_at = v_now, deletion_reason = pg_catalog.btrim(p_reason)
  where id = p_evidence_id and deleted_at is null;
  if not found then raise exception 'Active evidence item does not exist'; end if;

  insert into public.audit_events (
    id, occurred_at, actor_operational_person_id, operational_account_id,
    capability_id, action_code, source_area, subject_table, subject_id, cause
  ) values (
    pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
    v_actor.operational_account_id, v_actor.capability_id,
    'delivery_evidence.logically_deleted', 'delivery',
    'delivery_evidence_items', p_evidence_id, pg_catalog.btrim(p_reason)
  );
  return p_evidence_id;
end;
$$;

revoke all on function private.delete_delivery_evidence(uuid, text) from PUBLIC;
revoke all on function private.delete_delivery_evidence(uuid, text) from anon;
revoke all on function private.delete_delivery_evidence(uuid, text) from authenticated;
grant execute on function private.delete_delivery_evidence(uuid, text) to authenticated;

create function public.delete_delivery_evidence(p_evidence_id uuid, p_reason text)
returns uuid language sql volatile security invoker set search_path = pg_catalog
as $$ select private.delete_delivery_evidence(p_evidence_id, p_reason) $$;

revoke all on function public.delete_delivery_evidence(uuid, text) from PUBLIC;
revoke all on function public.delete_delivery_evidence(uuid, text) from anon;
revoke all on function public.delete_delivery_evidence(uuid, text) from authenticated;
grant execute on function public.delete_delivery_evidence(uuid, text) to authenticated;

grant usage on schema private to anon;

create function private.submit_support_request(
  p_subject text,
  p_purpose text,
  p_body text,
  p_contact_email text default null,
  p_contact_phone text default null,
  p_is_sensitive boolean default false,
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
  v_auth_user_id uuid := auth.uid();
  v_personal_account_id uuid;
  v_customer_id uuid;
  v_requester_kind text := 'visitor';
  v_request_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_retention_class text := '14_day';
  v_email text := nullif(pg_catalog.btrim(p_contact_email), '');
  v_phone text := nullif(pg_catalog.btrim(p_contact_phone), '');
  v_product_id uuid;
  v_presentation_id uuid;
  v_package_id uuid;
  v_order_id uuid;
begin
  if nullif(pg_catalog.btrim(p_subject), '') is null or pg_catalog.char_length(pg_catalog.btrim(p_subject)) > 160 then
    raise exception 'Subject is required and must not exceed 160 characters';
  end if;
  if nullif(pg_catalog.btrim(p_purpose), '') is null or pg_catalog.char_length(pg_catalog.btrim(p_purpose)) > 500 then
    raise exception 'Purpose is required and must not exceed 500 characters';
  end if;
  if nullif(pg_catalog.btrim(p_body), '') is null or pg_catalog.char_length(pg_catalog.btrim(p_body)) > 4000 then
    raise exception 'Message is required and must not exceed 4000 characters';
  end if;

  if v_auth_user_id is not null then
    select account.id, account.customer_id, coalesce(v_email, customer.contact_email), coalesce(v_phone, customer.contact_phone)
    into v_personal_account_id, v_customer_id, v_email, v_phone
    from public.personal_accounts account
    join public.customers customer on customer.id = account.customer_id
    where account.auth_user_id = v_auth_user_id and account.status = 'active'
    limit 1;
    if found then
      v_requester_kind := 'account';
    else
      v_email := nullif(pg_catalog.btrim(p_contact_email), '');
      v_phone := nullif(pg_catalog.btrim(p_contact_phone), '');
    end if;
  end if;

  if v_requester_kind = 'visitor' and v_email is null and v_phone is null then
    raise exception 'Email or phone is required for visitor support';
  end if;

  if p_reference_kind is null and p_reference_id is not null
    or p_reference_kind is not null and p_reference_id is null then
    raise exception 'Reference kind and id must be provided together';
  end if;

  if p_reference_kind = 'product' then
    if not exists (select 1 from public.products where id = p_reference_id and is_active and archived_at is null) then raise exception 'Product does not exist'; end if;
    v_product_id := p_reference_id;
  elsif p_reference_kind = 'presentation' then
    if not exists (select 1 from public.sellable_presentations where id = p_reference_id and is_active and archived_at is null) then raise exception 'Presentation does not exist'; end if;
    v_presentation_id := p_reference_id;
  elsif p_reference_kind = 'package' then
    if not exists (select 1 from public.packages where id = p_reference_id and is_active and archived_at is null) then raise exception 'Package does not exist'; end if;
    v_package_id := p_reference_id;
  elsif p_reference_kind = 'order' then
    if v_personal_account_id is null or not exists (
      select 1 from public.orders
      where id = p_reference_id and customer_id = v_customer_id
    ) then raise exception 'Order does not belong to the current Personal Account'; end if;
    v_order_id := p_reference_id;
    v_retention_class := '90_day';
  elsif p_reference_kind is not null then
    raise exception 'Unsupported support reference';
  end if;

  insert into public.support_requests (
    id, requester_kind, customer_id, personal_account_id,
    pseudonymous_reference, contact_email, contact_phone,
    subject, purpose, status, product_id, presentation_id,
    package_id, order_id, opened_at, retention_class
  ) values (
    v_request_id, v_requester_kind, null,
    case when v_requester_kind = 'account' then v_personal_account_id else null end,
    case when v_requester_kind = 'visitor' then v_request_id::text else null end,
    v_email, v_phone, pg_catalog.btrim(p_subject), pg_catalog.btrim(p_purpose),
    'open', v_product_id, v_presentation_id, v_package_id, v_order_id,
    v_now, v_retention_class
  );

  insert into public.support_messages (
    id, support_request_id, direction, author_kind,
    body, channel, is_sensitive, sent_at
  ) values (
    pg_catalog.gen_random_uuid(), v_request_id, 'incoming',
    case when v_requester_kind = 'account' then 'customer' else 'visitor' end,
    pg_catalog.btrim(p_body), 'internal', p_is_sensitive, v_now
  );

  return pg_catalog.jsonb_build_object(
    'request_id', v_request_id,
    'reference', case when v_requester_kind = 'visitor' then v_request_id::text else null end,
    'status', 'open'
  );
end;
$$;

revoke all on function private.submit_support_request(text, text, text, text, text, boolean, text, uuid) from PUBLIC;
revoke all on function private.submit_support_request(text, text, text, text, text, boolean, text, uuid) from anon;
revoke all on function private.submit_support_request(text, text, text, text, text, boolean, text, uuid) from authenticated;
grant execute on function private.submit_support_request(text, text, text, text, text, boolean, text, uuid) to anon, authenticated;

create function public.submit_support_request(
  p_subject text,
  p_purpose text,
  p_body text,
  p_contact_email text default null,
  p_contact_phone text default null,
  p_is_sensitive boolean default false,
  p_reference_kind text default null,
  p_reference_id uuid default null
)
returns jsonb language sql volatile security invoker set search_path = pg_catalog
as $$
  select private.submit_support_request(
    p_subject, p_purpose, p_body, p_contact_email, p_contact_phone,
    p_is_sensitive, p_reference_kind, p_reference_id
  )
$$;

revoke all on function public.submit_support_request(text, text, text, text, text, boolean, text, uuid) from PUBLIC;
revoke all on function public.submit_support_request(text, text, text, text, text, boolean, text, uuid) from anon;
revoke all on function public.submit_support_request(text, text, text, text, text, boolean, text, uuid) from authenticated;
grant execute on function public.submit_support_request(text, text, text, text, text, boolean, text, uuid) to anon, authenticated;

create function private.support_requests_view(p_request_id uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_personal_account_id uuid;
  v_can_handle boolean := private.has_capability('support.handle');
  v_can_sensitive boolean := private.has_capability('support.sensitive');
  v_actor record;
  v_result jsonb;
  v_is_sensitive boolean := false;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;

  select id into v_personal_account_id
  from public.personal_accounts
  where auth_user_id = auth.uid() and status = 'active'
  limit 1;

  if not v_can_handle and v_personal_account_id is null then
    raise exception 'Support access is not available';
  end if;

  if p_request_id is null then
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(request_row) order by request_row.opened_at desc), '[]'::jsonb)
    into v_result
    from public.support_requests request_row
    where request_row.deleted_at is null
      and (
        (v_can_handle and (
          v_can_sensitive or not exists (
            select 1 from public.support_messages message
            where message.support_request_id = request_row.id and message.is_sensitive
          )
        ))
        or request_row.personal_account_id = v_personal_account_id
      );
    return v_result;
  end if;

  select exists (
    select 1 from public.support_messages
    where support_request_id = p_request_id and is_sensitive
  ) into v_is_sensitive;

  select pg_catalog.jsonb_build_object(
    'request', pg_catalog.to_jsonb(request_row),
    'messages', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(message) order by message.sent_at)
      from public.support_messages message
      where message.support_request_id = request_row.id
    ), '[]'::jsonb)
  ) into v_result
  from public.support_requests request_row
  where request_row.id = p_request_id
    and request_row.deleted_at is null
    and (
      (v_can_handle and (not v_is_sensitive or v_can_sensitive))
      or request_row.personal_account_id = v_personal_account_id
    );

  if v_result is null then raise exception 'Support request does not exist or is not accessible'; end if;

  if v_can_handle and v_is_sensitive then
    select * into v_actor from private.resolve_operational_actor(array['support.sensitive']);
    insert into public.audit_events (
      id, occurred_at, actor_operational_person_id, operational_account_id,
      capability_id, action_code, source_area, subject_table, subject_id, cause
    ) values (
      pg_catalog.gen_random_uuid(), pg_catalog.clock_timestamp(),
      v_actor.operational_person_id, v_actor.operational_account_id, v_actor.capability_id,
      'support.sensitive_viewed', 'support', 'support_requests', p_request_id,
      'Acceso operativo a conversación sensible'
    );
  end if;

  return v_result;
end;
$$;

revoke all on function private.support_requests_view(uuid) from PUBLIC;
revoke all on function private.support_requests_view(uuid) from anon;
revoke all on function private.support_requests_view(uuid) from authenticated;
grant execute on function private.support_requests_view(uuid) to authenticated;

create function public.support_requests_view(p_request_id uuid default null)
returns jsonb language sql volatile security invoker set search_path = pg_catalog
as $$ select private.support_requests_view(p_request_id) $$;

revoke all on function public.support_requests_view(uuid) from PUBLIC;
revoke all on function public.support_requests_view(uuid) from anon;
revoke all on function public.support_requests_view(uuid) from authenticated;
grant execute on function public.support_requests_view(uuid) to authenticated;

create function private.respond_support_request(
  p_request_id uuid,
  p_body text,
  p_is_sensitive boolean default false
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
  v_message_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  select * into v_actor from private.resolve_operational_actor(
    case when p_is_sensitive then array['support.sensitive'] else array['support.handle'] end
  );
  if v_actor.operational_account_id is null then raise exception 'Missing required support capability'; end if;
  if p_is_sensitive and not private.has_capability('support.handle') then
    raise exception 'support.handle is also required to respond';
  end if;
  if nullif(pg_catalog.btrim(p_body), '') is null or pg_catalog.char_length(pg_catalog.btrim(p_body)) > 4000 then
    raise exception 'Response is required and must not exceed 4000 characters';
  end if;

  select * into v_request from public.support_requests where id = p_request_id for update;
  if not found or v_request.deleted_at is not null then raise exception 'Support request does not exist'; end if;
  if v_request.status = 'closed' then raise exception 'Closed support request cannot receive responses'; end if;
  if exists (
    select 1 from public.support_messages where support_request_id = p_request_id and is_sensitive
  ) and not private.has_capability('support.sensitive') then
    raise exception 'support.sensitive is required for this request';
  end if;

  insert into public.support_messages (
    id, support_request_id, direction, author_kind,
    operational_person_id, operational_account_id, capability_id,
    body, channel, is_sensitive, sent_at
  ) values (
    v_message_id, p_request_id, 'outgoing', 'operational_person',
    v_actor.operational_person_id, v_actor.operational_account_id, v_actor.capability_id,
    pg_catalog.btrim(p_body), 'internal', p_is_sensitive, v_now
  );

  update public.support_requests
  set status = case when status = 'open' then 'in_attention' else status end,
      updated_at = v_now
  where id = p_request_id;

  if p_is_sensitive then
    insert into public.audit_events (
      id, occurred_at, actor_operational_person_id, operational_account_id,
      capability_id, action_code, source_area, subject_table, subject_id, cause
    ) values (
      pg_catalog.gen_random_uuid(), v_now, v_actor.operational_person_id,
      v_actor.operational_account_id, v_actor.capability_id,
      'support.sensitive_response', 'support', 'support_requests', p_request_id,
      'Respuesta operativa marcada como sensible'
    );
  end if;

  return v_message_id;
end;
$$;

revoke all on function private.respond_support_request(uuid, text, boolean) from PUBLIC;
revoke all on function private.respond_support_request(uuid, text, boolean) from anon;
revoke all on function private.respond_support_request(uuid, text, boolean) from authenticated;
grant execute on function private.respond_support_request(uuid, text, boolean) to authenticated;

create function public.respond_support_request(p_request_id uuid, p_body text, p_is_sensitive boolean default false)
returns uuid language sql volatile security invoker set search_path = pg_catalog
as $$ select private.respond_support_request(p_request_id, p_body, p_is_sensitive) $$;

revoke all on function public.respond_support_request(uuid, text, boolean) from PUBLIC;
revoke all on function public.respond_support_request(uuid, text, boolean) from anon;
revoke all on function public.respond_support_request(uuid, text, boolean) from authenticated;
grant execute on function public.respond_support_request(uuid, text, boolean) to authenticated;

create function private.set_support_request_status(
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
  v_retention_due_at timestamptz;
  v_is_sensitive boolean;
begin
  select * into v_actor from private.resolve_operational_actor(array['support.handle']);
  if v_actor.operational_account_id is null then raise exception 'Missing support.handle capability'; end if;
  if p_status not in ('open', 'in_attention', 'resolved', 'channelled', 'closed') then raise exception 'Unsupported support status'; end if;

  select * into v_request from public.support_requests where id = p_request_id for update;
  if not found or v_request.deleted_at is not null then raise exception 'Support request does not exist'; end if;
  select exists (select 1 from public.support_messages where support_request_id = p_request_id and is_sensitive)
  into v_is_sensitive;
  if v_is_sensitive and not private.has_capability('support.sensitive') then raise exception 'support.sensitive is required for this request'; end if;

  if p_status = 'closed' and nullif(pg_catalog.btrim(p_cause), '') is null then raise exception 'Closure reason is required'; end if;
  if p_status = 'closed' then
    v_retention_due_at := v_now + case v_request.retention_class when '14_day' then interval '14 days' else interval '90 days' end;
  end if;

  if (p_reference_kind is null) <> (p_reference_id is null) then raise exception 'Reference kind and id must be provided together'; end if;
  if p_reference_kind is not null then
    if p_reference_kind = 'order' and not exists (select 1 from public.orders where id = p_reference_id) then raise exception 'Order does not exist';
    elsif p_reference_kind = 'preparation' and not exists (select 1 from public.preparations where id = p_reference_id) then raise exception 'Preparation does not exist';
    elsif p_reference_kind = 'delivery' and not exists (select 1 from public.deliveries where id = p_reference_id) then raise exception 'Delivery does not exist';
    elsif p_reference_kind not in ('order', 'preparation', 'delivery') then raise exception 'Unsupported operational reference';
    end if;

    update public.support_requests
    set product_id = null, presentation_id = null, package_id = null,
        order_id = case when p_reference_kind = 'order' then p_reference_id else null end,
        preparation_id = case when p_reference_kind = 'preparation' then p_reference_id else null end,
        delivery_id = case when p_reference_kind = 'delivery' then p_reference_id else null end,
        retention_class = '90_day'
    where id = p_request_id;
  end if;

  update public.support_requests
  set status = p_status,
      closed_at = case when p_status = 'closed' then v_now else null end,
      closure_reason = case when p_status = 'closed' then pg_catalog.btrim(p_cause) else null end,
      retention_due_at = case when p_status = 'closed' then
        v_now + case retention_class when '14_day' then interval '14 days' else interval '90 days' end
        else null end,
      updated_at = v_now
  where id = p_request_id;

  return pg_catalog.jsonb_build_object('request_id', p_request_id, 'status', p_status, 'retention_due_at', v_retention_due_at);
end;
$$;

revoke all on function private.set_support_request_status(uuid, text, text, text, uuid) from PUBLIC;
revoke all on function private.set_support_request_status(uuid, text, text, text, uuid) from anon;
revoke all on function private.set_support_request_status(uuid, text, text, text, uuid) from authenticated;
grant execute on function private.set_support_request_status(uuid, text, text, text, uuid) to authenticated;

create function public.set_support_request_status(
  p_request_id uuid,
  p_status text,
  p_cause text default null,
  p_reference_kind text default null,
  p_reference_id uuid default null
)
returns jsonb language sql volatile security invoker set search_path = pg_catalog
as $$ select private.set_support_request_status(p_request_id, p_status, p_cause, p_reference_kind, p_reference_id) $$;

revoke all on function public.set_support_request_status(uuid, text, text, text, uuid) from PUBLIC;
revoke all on function public.set_support_request_status(uuid, text, text, text, uuid) from anon;
revoke all on function public.set_support_request_status(uuid, text, text, text, uuid) from authenticated;
grant execute on function public.set_support_request_status(uuid, text, text, text, uuid) to authenticated;
