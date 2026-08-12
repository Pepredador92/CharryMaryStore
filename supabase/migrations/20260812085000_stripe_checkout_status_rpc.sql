create function public.get_stripe_checkout_status(
  p_checkout_session_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_status jsonb;
begin
  select pg_catalog.jsonb_build_object(
    'order_id', public.orders.id,
    'order_number', public.orders.order_number,
    'commercial_status', public.orders.commercial_status,
    'total_amount_minor', public.orders.total_amount_minor,
    'currency_code', public.orders.currency_code,
    'payment_status', public.order_payments.status
  )
  into v_status
  from public.order_payments
  join public.orders
    on public.orders.id = public.order_payments.order_id
  where public.order_payments.provider_checkout_session_id = p_checkout_session_id;

  if v_status is null then
    raise exception 'Stripe Checkout Session was not found';
  end if;

  return v_status;
end;
$$;

revoke all on function public.get_stripe_checkout_status(text) from PUBLIC;
revoke all on function public.get_stripe_checkout_status(text) from anon;
revoke all on function public.get_stripe_checkout_status(text) from authenticated;
grant execute on function public.get_stripe_checkout_status(text) to service_role;
