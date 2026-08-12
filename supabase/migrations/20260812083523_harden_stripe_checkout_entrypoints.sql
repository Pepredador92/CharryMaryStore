create function private.place_authenticated_order_for_payment(
  p_cart_id uuid,
  p_destination jsonb,
  p_payment_token uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_existing_order_id uuid;
  v_existing_auth_user_id uuid;
  v_confirmation jsonb;
begin
  if p_payment_token is null then
    raise exception 'Payment token is required';
  end if;

  select
    private.stripe_checkout_requests.order_id,
    private.stripe_checkout_requests.auth_user_id
  into v_existing_order_id, v_existing_auth_user_id
  from private.stripe_checkout_requests
  where private.stripe_checkout_requests.payment_token = p_payment_token;

  if found then
    if v_existing_auth_user_id is distinct from auth.uid() then
      raise exception 'Payment request does not belong to this account';
    end if;

    select pg_catalog.jsonb_build_object(
      'order_id', public.orders.id,
      'order_number', public.orders.order_number,
      'currency_code', public.orders.currency_code,
      'total_amount_minor', public.orders.total_amount_minor,
      'commercial_status', public.orders.commercial_status,
      'payment_token', p_payment_token
    )
    into v_confirmation
    from public.orders
    where public.orders.id = v_existing_order_id;

    return v_confirmation;
  end if;

  v_confirmation := private.place_authenticated_order(p_cart_id, p_destination);

  insert into private.stripe_checkout_requests (
    payment_token,
    order_id,
    auth_user_id
  )
  values (
    p_payment_token,
    (v_confirmation ->> 'order_id')::uuid,
    auth.uid()
  );

  return v_confirmation || pg_catalog.jsonb_build_object('payment_token', p_payment_token);
end;
$$;

revoke all on function private.place_authenticated_order_for_payment(uuid, jsonb, uuid) from PUBLIC;
revoke all on function private.place_authenticated_order_for_payment(uuid, jsonb, uuid) from anon;
revoke all on function private.place_authenticated_order_for_payment(uuid, jsonb, uuid) from authenticated;
grant execute on function private.place_authenticated_order_for_payment(uuid, jsonb, uuid) to authenticated;

create function private.place_guest_order_for_payment(
  p_items jsonb,
  p_destination jsonb,
  p_payment_token uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_existing_order_id uuid;
  v_existing_auth_user_id uuid;
  v_confirmation jsonb;
begin
  if auth.uid() is not null then
    raise exception 'Signed-in customers must use authenticated checkout';
  end if;

  if p_payment_token is null then
    raise exception 'Payment token is required';
  end if;

  select
    private.stripe_checkout_requests.order_id,
    private.stripe_checkout_requests.auth_user_id
  into v_existing_order_id, v_existing_auth_user_id
  from private.stripe_checkout_requests
  where private.stripe_checkout_requests.payment_token = p_payment_token;

  if found then
    if v_existing_auth_user_id is not null then
      raise exception 'Payment request requires authentication';
    end if;

    select pg_catalog.jsonb_build_object(
      'order_id', public.orders.id,
      'order_number', public.orders.order_number,
      'currency_code', public.orders.currency_code,
      'total_amount_minor', public.orders.total_amount_minor,
      'commercial_status', public.orders.commercial_status,
      'payment_token', p_payment_token
    )
    into v_confirmation
    from public.orders
    where public.orders.id = v_existing_order_id;

    return v_confirmation;
  end if;

  v_confirmation := private.place_guest_order(p_items, p_destination);

  insert into private.stripe_checkout_requests (
    payment_token,
    order_id,
    auth_user_id
  )
  values (
    p_payment_token,
    (v_confirmation ->> 'order_id')::uuid,
    null
  );

  return v_confirmation || pg_catalog.jsonb_build_object('payment_token', p_payment_token);
end;
$$;

revoke all on function private.place_guest_order_for_payment(jsonb, jsonb, uuid) from PUBLIC;
revoke all on function private.place_guest_order_for_payment(jsonb, jsonb, uuid) from anon;
revoke all on function private.place_guest_order_for_payment(jsonb, jsonb, uuid) from authenticated;
grant execute on function private.place_guest_order_for_payment(jsonb, jsonb, uuid) to anon;

create or replace function public.place_authenticated_order_for_payment(
  p_cart_id uuid,
  p_destination jsonb,
  p_payment_token uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.place_authenticated_order_for_payment(
    p_cart_id,
    p_destination,
    p_payment_token
  )
$$;

revoke all on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) from PUBLIC;
revoke all on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) from anon;
revoke all on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) from authenticated;
grant execute on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) to authenticated;

create or replace function public.place_guest_order_for_payment(
  p_items jsonb,
  p_destination jsonb,
  p_payment_token uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.place_guest_order_for_payment(
    p_items,
    p_destination,
    p_payment_token
  )
$$;

revoke all on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) from PUBLIC;
revoke all on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) from anon;
revoke all on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) from authenticated;
grant execute on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) to anon;
