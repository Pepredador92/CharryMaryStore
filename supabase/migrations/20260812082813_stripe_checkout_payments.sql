create table private.stripe_checkout_requests (
  payment_token uuid not null,
  order_id uuid not null,
  auth_user_id uuid null,
  latest_checkout_session_id text null,
  status text not null default 'prepared',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_stripe_checkout_requests primary key (payment_token),
  constraint fk_stripe_checkout_requests__orders
    foreign key (order_id)
    references public.orders (id)
    on delete restrict,
  constraint uq_stripe_checkout_requests__order_id unique (order_id),
  constraint uq_stripe_checkout_requests__latest_checkout_session_id
    unique (latest_checkout_session_id),
  constraint ck_stripe_checkout_requests__status check (
    status in ('prepared', 'checkout_created', 'processing', 'paid', 'failed', 'expired')
  )
);

revoke all on table private.stripe_checkout_requests from PUBLIC;
revoke all on table private.stripe_checkout_requests from anon;
revoke all on table private.stripe_checkout_requests from authenticated;

create table private.stripe_webhook_events (
  event_id text not null,
  event_type text not null,
  checkout_session_id text null,
  received_at timestamptz not null default now(),
  processed_at timestamptz not null default now(),
  constraint pk_stripe_webhook_events primary key (event_id)
);

revoke all on table private.stripe_webhook_events from PUBLIC;
revoke all on table private.stripe_webhook_events from anon;
revoke all on table private.stripe_webhook_events from authenticated;

create table public.order_payments (
  id uuid not null,
  order_id uuid not null,
  provider text not null,
  status text not null,
  amount_minor bigint not null,
  currency_code char(3) not null,
  provider_checkout_session_id text not null,
  provider_payment_intent_id text null,
  paid_at timestamptz null,
  failed_at timestamptz null,
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_order_payments primary key (id),
  constraint fk_order_payments__orders
    foreign key (order_id)
    references public.orders (id)
    on delete restrict,
  constraint uq_order_payments__provider_checkout_session_id
    unique (provider_checkout_session_id),
  constraint ck_order_payments__provider check (provider = 'stripe'),
  constraint ck_order_payments__status check (
    status in ('pending', 'processing', 'paid', 'failed', 'expired')
  ),
  constraint ck_order_payments__amount_minor check (amount_minor > 0),
  constraint ck_order_payments__paid_at check (
    (status = 'paid' and paid_at is not null)
    or (status <> 'paid' and paid_at is null)
  ),
  constraint ck_order_payments__failed_at check (
    (status = 'failed' and failed_at is not null)
    or (status <> 'failed' and failed_at is null)
  )
);

create index ix_order_payments__order_id
  on public.order_payments (order_id);

create unique index uq_order_payments__provider_payment_intent_id
  on public.order_payments (provider_payment_intent_id)
  where provider_payment_intent_id is not null;

create unique index uq_order_payments__order_id_current
  on public.order_payments (order_id)
  where status in ('pending', 'processing');

alter table public.order_payments enable row level security;

revoke all on table public.order_payments from PUBLIC;
revoke all on table public.order_payments from anon;
revoke all on table public.order_payments from authenticated;
grant select on table public.order_payments to authenticated;

create policy pol_order_payments__personal_select
  on public.order_payments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.orders
      join public.personal_accounts
        on public.personal_accounts.customer_id = public.orders.customer_id
      where public.orders.id = public.order_payments.order_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_order_payments__operational_select
  on public.order_payments
  for select
  to authenticated
  using (
    (select private.has_capability('orders.read'))
    or (select private.has_capability('orders.manage'))
  );

create function public.place_authenticated_order_for_payment(
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

revoke all on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) from PUBLIC;
revoke all on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) from anon;
revoke all on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) from authenticated;
grant execute on function public.place_authenticated_order_for_payment(uuid, jsonb, uuid) to authenticated;

create function public.place_guest_order_for_payment(
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

revoke all on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) from PUBLIC;
revoke all on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) from anon;
revoke all on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) from authenticated;
grant execute on function public.place_guest_order_for_payment(jsonb, jsonb, uuid) to anon;

create function public.get_stripe_checkout_payload(
  p_order_id uuid,
  p_payment_token uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_payload jsonb;
begin
  perform 1
  from private.stripe_checkout_requests
  where private.stripe_checkout_requests.order_id = p_order_id
    and private.stripe_checkout_requests.payment_token = p_payment_token;

  if not found then
    raise exception 'Payment request was not found';
  end if;

  if exists (
    select 1
    from public.order_payments
    where public.order_payments.order_id = p_order_id
      and public.order_payments.status = 'paid'
  ) then
    raise exception 'Order is already paid';
  end if;

  select pg_catalog.jsonb_build_object(
    'order_id', public.orders.id,
    'order_number', public.orders.order_number,
    'amount_minor', public.orders.total_amount_minor,
    'currency_code', public.orders.currency_code,
    'customer_email', public.order_destinations.contact_email,
    'latest_checkout_session_id', private.stripe_checkout_requests.latest_checkout_session_id
  )
  into v_payload
  from public.orders
  join private.stripe_checkout_requests
    on private.stripe_checkout_requests.order_id = public.orders.id
  left join public.order_destinations
    on public.order_destinations.order_id = public.orders.id
    and public.order_destinations.is_current = true
  where public.orders.id = p_order_id;

  if (v_payload ->> 'amount_minor')::bigint <= 0 then
    raise exception 'Order total must be greater than zero';
  end if;

  return v_payload;
end;
$$;

revoke all on function public.get_stripe_checkout_payload(uuid, uuid) from PUBLIC;
revoke all on function public.get_stripe_checkout_payload(uuid, uuid) from anon;
revoke all on function public.get_stripe_checkout_payload(uuid, uuid) from authenticated;
grant execute on function public.get_stripe_checkout_payload(uuid, uuid) to service_role;

create function public.record_stripe_checkout_session(
  p_order_id uuid,
  p_payment_token uuid,
  p_checkout_session_id text,
  p_amount_minor bigint,
  p_currency_code text,
  p_expires_at timestamptz
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_order_amount bigint;
  v_order_currency text;
begin
  perform 1
  from private.stripe_checkout_requests
  where private.stripe_checkout_requests.order_id = p_order_id
    and private.stripe_checkout_requests.payment_token = p_payment_token
  for update;

  if not found then
    raise exception 'Payment request was not found';
  end if;

  select public.orders.total_amount_minor, public.orders.currency_code::text
  into v_order_amount, v_order_currency
  from public.orders
  where public.orders.id = p_order_id;

  if v_order_amount <> p_amount_minor
    or pg_catalog.upper(v_order_currency) <> pg_catalog.upper(p_currency_code) then
    raise exception 'Stripe Checkout amount does not match the Order';
  end if;

  update public.order_payments
  set
    status = 'expired',
    updated_at = pg_catalog.now()
  where public.order_payments.order_id = p_order_id
    and public.order_payments.status in ('pending', 'processing')
    and public.order_payments.provider_checkout_session_id <> p_checkout_session_id;

  insert into public.order_payments (
    id,
    order_id,
    provider,
    status,
    amount_minor,
    currency_code,
    provider_checkout_session_id,
    expires_at
  )
  values (
    pg_catalog.gen_random_uuid(),
    p_order_id,
    'stripe',
    'pending',
    p_amount_minor,
    pg_catalog.upper(p_currency_code),
    p_checkout_session_id,
    p_expires_at
  )
  on conflict (provider_checkout_session_id) do nothing;

  update private.stripe_checkout_requests
  set
    latest_checkout_session_id = p_checkout_session_id,
    status = 'checkout_created',
    updated_at = pg_catalog.now()
  where private.stripe_checkout_requests.order_id = p_order_id;
end;
$$;

revoke all on function public.record_stripe_checkout_session(uuid, uuid, text, bigint, text, timestamptz) from PUBLIC;
revoke all on function public.record_stripe_checkout_session(uuid, uuid, text, bigint, text, timestamptz) from anon;
revoke all on function public.record_stripe_checkout_session(uuid, uuid, text, bigint, text, timestamptz) from authenticated;
grant execute on function public.record_stripe_checkout_session(uuid, uuid, text, bigint, text, timestamptz) to service_role;

create function public.apply_stripe_checkout_event(
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
    provider_payment_intent_id = pg_catalog.coalesce(
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
