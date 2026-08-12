create or replace function public.apply_stripe_checkout_event(
  p_event_id text,
  p_event_type text,
  p_order_id uuid,
  p_checkout_session_id text,
  p_payment_intent_id text,
  p_payment_status text,
  p_amount_minor bigint,
  p_currency_code text,
  p_occurred_at timestamptz
)
returns boolean
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_status text;
begin
  insert into private.stripe_webhook_events (
    event_id,
    event_type,
    checkout_session_id
  )
  values (
    p_event_id,
    p_event_type,
    p_checkout_session_id
  )
  on conflict (event_id) do nothing;

  if not found then
    return false;
  end if;

  if p_event_type in ('checkout.session.completed', 'checkout.session.async_payment_succeeded')
    and p_payment_status = 'paid' then
    v_status := 'paid';
  elsif p_event_type = 'checkout.session.completed' then
    v_status := 'processing';
  elsif p_event_type = 'checkout.session.async_payment_failed' then
    v_status := 'failed';
  elsif p_event_type = 'checkout.session.expired' then
    v_status := 'expired';
  else
    return true;
  end if;

  if v_status = 'paid' and not exists (
    select 1
    from public.order_payments
    where public.order_payments.order_id = p_order_id
      and public.order_payments.provider_checkout_session_id = p_checkout_session_id
      and public.order_payments.amount_minor = p_amount_minor
      and pg_catalog.upper(public.order_payments.currency_code::text) = pg_catalog.upper(p_currency_code)
  ) then
    raise exception 'Paid Stripe amount does not match the recorded Checkout Session';
  end if;

  update public.order_payments
  set
    status = v_status,
    provider_payment_intent_id = coalesce(
      p_payment_intent_id,
      public.order_payments.provider_payment_intent_id
    ),
    paid_at = case when v_status = 'paid' then p_occurred_at else null end,
    failed_at = case when v_status = 'failed' then p_occurred_at else null end,
    updated_at = pg_catalog.now()
  where public.order_payments.order_id = p_order_id
    and public.order_payments.provider_checkout_session_id = p_checkout_session_id;

  if not found then
    raise exception 'Stripe Checkout Session was not recorded';
  end if;

  update private.stripe_checkout_requests
  set
    status = case v_status
      when 'pending' then 'checkout_created'
      else v_status
    end,
    updated_at = pg_catalog.now()
  where private.stripe_checkout_requests.order_id = p_order_id;

  return true;
end;
$$;

revoke all on function public.apply_stripe_checkout_event(text, text, uuid, text, text, text, bigint, text, timestamptz) from PUBLIC;
revoke all on function public.apply_stripe_checkout_event(text, text, uuid, text, text, text, bigint, text, timestamptz) from anon;
revoke all on function public.apply_stripe_checkout_event(text, text, uuid, text, text, text, bigint, text, timestamptz) from authenticated;
grant execute on function public.apply_stripe_checkout_event(text, text, uuid, text, text, text, bigint, text, timestamptz) to service_role;
