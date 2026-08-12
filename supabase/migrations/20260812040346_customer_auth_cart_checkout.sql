grant select on table public.presentation_inventory to anon, authenticated;

create policy pol_presentation_inventory__public_select
  on public.presentation_inventory
  for select
  to anon, authenticated
  using (
    exists (
      select 1
      from public.sellable_presentations
      join public.products
        on public.products.id = public.sellable_presentations.product_id
      where public.sellable_presentations.id = public.presentation_inventory.presentation_id
        and public.sellable_presentations.is_active = true
        and public.sellable_presentations.archived_at is null
        and public.products.is_active = true
        and public.products.archived_at is null
    )
  );

create unique index uq_cart_lines__cart_id_package_id
  on public.cart_lines (cart_id, package_id)
  where package_id is not null;

create table private.cart_merge_operations (
  operation_id uuid not null,
  personal_account_id uuid not null,
  cart_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  constraint pk_cart_merge_operations primary key (operation_id),
  constraint fk_cart_merge_operations__personal_accounts
    foreign key (personal_account_id)
    references public.personal_accounts (id)
    on delete restrict,
  constraint fk_cart_merge_operations__carts
    foreign key (cart_id)
    references public.carts (id)
    on delete restrict
);

revoke all on table private.cart_merge_operations from PUBLIC;
revoke all on table private.cart_merge_operations from anon;
revoke all on table private.cart_merge_operations from authenticated;

create function private.current_personal_account_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select public.personal_accounts.id
  from public.personal_accounts
  where auth.uid() is not null
    and public.personal_accounts.auth_user_id = auth.uid()
    and public.personal_accounts.status = 'active'
  limit 1
$$;

revoke all on function private.current_personal_account_id() from PUBLIC;
revoke all on function private.current_personal_account_id() from anon;
revoke all on function private.current_personal_account_id() from authenticated;
grant execute on function private.current_personal_account_id() to authenticated;

create function private.ensure_personal_account(
  p_preferred_name text default null,
  p_contact_phone text default null
)
returns table (
  personal_account_id uuid,
  customer_id uuid,
  preferred_name text,
  contact_email text,
  contact_phone text,
  account_status text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_auth_email text;
  v_personal_account_id uuid;
  v_customer_id uuid;
  v_account_status text;
begin
  if v_auth_user_id is null then
    raise exception 'Authentication is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_auth_user_id::text, 0)
  );

  select
    public.personal_accounts.id,
    public.personal_accounts.customer_id,
    public.personal_accounts.status
  into
    v_personal_account_id,
    v_customer_id,
    v_account_status
  from public.personal_accounts
  where public.personal_accounts.auth_user_id = v_auth_user_id
  for update;

  if found and v_account_status <> 'active' then
    raise exception 'Personal account is not active';
  end if;

  if not found then
    select auth.users.email
    into v_auth_email
    from auth.users
    where auth.users.id = v_auth_user_id;

    if not found then
      raise exception 'Authenticated user does not exist';
    end if;

    v_customer_id := pg_catalog.gen_random_uuid();
    v_personal_account_id := pg_catalog.gen_random_uuid();

    insert into public.customers (
      id,
      preferred_name,
      contact_email,
      contact_phone,
      status
    )
    values (
      v_customer_id,
      nullif(pg_catalog.btrim(p_preferred_name), ''),
      nullif(pg_catalog.btrim(v_auth_email), ''),
      nullif(pg_catalog.btrim(p_contact_phone), ''),
      'active'
    );

    insert into public.personal_accounts (
      id,
      customer_id,
      auth_user_id,
      status
    )
    values (
      v_personal_account_id,
      v_customer_id,
      v_auth_user_id,
      'active'
    );
  end if;

  return query
  select
    public.personal_accounts.id,
    public.customers.id,
    public.customers.preferred_name,
    public.customers.contact_email,
    public.customers.contact_phone,
    public.personal_accounts.status
  from public.personal_accounts
  join public.customers
    on public.customers.id = public.personal_accounts.customer_id
  where public.personal_accounts.id = v_personal_account_id;
end;
$$;

revoke all on function private.ensure_personal_account(text, text) from PUBLIC;
revoke all on function private.ensure_personal_account(text, text) from anon;
revoke all on function private.ensure_personal_account(text, text) from authenticated;
grant execute on function private.ensure_personal_account(text, text) to authenticated;

create function public.ensure_personal_account(
  p_preferred_name text default null,
  p_contact_phone text default null
)
returns table (
  personal_account_id uuid,
  customer_id uuid,
  preferred_name text,
  contact_email text,
  contact_phone text,
  account_status text
)
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select *
  from private.ensure_personal_account(p_preferred_name, p_contact_phone)
$$;

revoke all on function public.ensure_personal_account(text, text) from PUBLIC;
revoke all on function public.ensure_personal_account(text, text) from anon;
revoke all on function public.ensure_personal_account(text, text) from authenticated;
grant execute on function public.ensure_personal_account(text, text) to authenticated;

create function private.get_or_create_current_cart()
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_personal_account_id uuid;
  v_cart_id uuid;
  v_now timestamptz := pg_catalog.now();
begin
  v_personal_account_id := private.current_personal_account_id();

  if v_personal_account_id is null then
    raise exception 'An active Personal Account is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_personal_account_id::text, 1)
  );

  update public.carts
  set
    status = 'expired',
    updated_at = v_now
  where public.carts.personal_account_id = v_personal_account_id
    and public.carts.status in ('active', 'inactive')
    and public.carts.expires_at <= v_now;

  select public.carts.id
  into v_cart_id
  from public.carts
  where public.carts.personal_account_id = v_personal_account_id
    and public.carts.status in ('active', 'inactive')
  order by public.carts.created_at desc
  limit 1
  for update;

  if not found then
    v_cart_id := pg_catalog.gen_random_uuid();

    insert into public.carts (
      id,
      personal_account_id,
      status,
      last_meaningful_activity_at,
      expires_at
    )
    values (
      v_cart_id,
      v_personal_account_id,
      'active',
      v_now,
      v_now + interval '60 days'
    );
  end if;

  return v_cart_id;
end;
$$;

revoke all on function private.get_or_create_current_cart() from PUBLIC;
revoke all on function private.get_or_create_current_cart() from anon;
revoke all on function private.get_or_create_current_cart() from authenticated;
grant execute on function private.get_or_create_current_cart() to authenticated;

create function public.get_or_create_current_cart()
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.get_or_create_current_cart()
$$;

revoke all on function public.get_or_create_current_cart() from PUBLIC;
revoke all on function public.get_or_create_current_cart() from anon;
revoke all on function public.get_or_create_current_cart() from authenticated;
grant execute on function public.get_or_create_current_cart() to authenticated;

create function private.catalog_item_updated_at(
  p_line_kind text,
  p_target_id uuid
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_updated_at timestamptz;
  v_component_count integer;
  v_valid_component_count integer;
begin
  if p_line_kind = 'presentation' then
    select greatest(
      public.sellable_presentations.updated_at,
      public.products.updated_at
    )
    into v_updated_at
    from public.sellable_presentations
    join public.products
      on public.products.id = public.sellable_presentations.product_id
    where public.sellable_presentations.id = p_target_id
      and public.sellable_presentations.is_active = true
      and public.sellable_presentations.archived_at is null
      and public.products.is_active = true
      and public.products.archived_at is null;
  elsif p_line_kind = 'package' then
    select
      greatest(
        public.packages.updated_at,
        pg_catalog.max(public.package_components.updated_at),
        pg_catalog.max(public.sellable_presentations.updated_at),
        pg_catalog.max(public.products.updated_at)
      ),
      pg_catalog.count(public.package_components.id)::integer,
      pg_catalog.count(public.package_components.id) filter (
        where public.sellable_presentations.is_active = true
          and public.sellable_presentations.archived_at is null
          and public.products.is_active = true
          and public.products.archived_at is null
      )::integer
    into v_updated_at, v_component_count, v_valid_component_count
    from public.packages
    join public.package_components
      on public.package_components.package_id = public.packages.id
      and public.package_components.is_active = true
    left join public.sellable_presentations
      on public.sellable_presentations.id = public.package_components.presentation_id
    left join public.products
      on public.products.id = public.sellable_presentations.product_id
    where public.packages.id = p_target_id
      and public.packages.is_active = true
      and public.packages.archived_at is null
      and (public.packages.valid_from is null or public.packages.valid_from <= pg_catalog.now())
      and (public.packages.valid_until is null or public.packages.valid_until > pg_catalog.now())
    group by public.packages.id, public.packages.updated_at;

    if coalesce(v_component_count, 0) = 0
      or v_component_count <> v_valid_component_count then
      v_updated_at := null;
    end if;
  else
    raise exception 'Unsupported cart line kind';
  end if;

  if v_updated_at is null then
    raise exception 'Catalog item is not currently sellable';
  end if;

  return v_updated_at;
end;
$$;

revoke all on function private.catalog_item_updated_at(text, uuid) from PUBLIC;
revoke all on function private.catalog_item_updated_at(text, uuid) from anon;
revoke all on function private.catalog_item_updated_at(text, uuid) from authenticated;

create function private.set_authenticated_cart_item(
  p_line_kind text,
  p_target_id uuid,
  p_quantity integer,
  p_mode text default 'set'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_cart_id uuid;
  v_line_id uuid;
  v_catalog_updated_at timestamptz;
  v_final_quantity integer;
  v_now timestamptz := pg_catalog.now();
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if p_line_kind not in ('presentation', 'package') then
    raise exception 'Unsupported cart line kind';
  end if;

  if p_target_id is null then
    raise exception 'Catalog target is required';
  end if;

  if p_quantity is null or p_quantity < 0 or p_quantity > 99 then
    raise exception 'Quantity must be between 0 and 99';
  end if;

  if p_mode not in ('set', 'add') then
    raise exception 'Unsupported cart operation mode';
  end if;

  v_cart_id := private.get_or_create_current_cart();

  perform 1
  from public.carts
  where public.carts.id = v_cart_id
  for update;

  if p_line_kind = 'presentation' then
    select public.cart_lines.id, public.cart_lines.quantity
    into v_line_id, v_final_quantity
    from public.cart_lines
    where public.cart_lines.cart_id = v_cart_id
      and public.cart_lines.presentation_id = p_target_id
    for update;
  else
    select public.cart_lines.id, public.cart_lines.quantity
    into v_line_id, v_final_quantity
    from public.cart_lines
    where public.cart_lines.cart_id = v_cart_id
      and public.cart_lines.package_id = p_target_id
    for update;
  end if;

  if p_mode = 'add' then
    v_final_quantity := coalesce(v_final_quantity, 0) + p_quantity;
  else
    v_final_quantity := p_quantity;
  end if;

  if v_final_quantity > 99 then
    raise exception 'Quantity cannot exceed 99';
  end if;

  if v_final_quantity = 0 then
    if v_line_id is not null then
      delete from public.cart_lines
      where public.cart_lines.id = v_line_id;
    end if;
  else
    v_catalog_updated_at := private.catalog_item_updated_at(p_line_kind, p_target_id);

    if v_line_id is null then
      v_line_id := pg_catalog.gen_random_uuid();

      insert into public.cart_lines (
        id,
        cart_id,
        line_kind,
        presentation_id,
        package_id,
        quantity,
        catalog_updated_at_seen,
        validation_status,
        last_validated_at
      )
      values (
        v_line_id,
        v_cart_id,
        p_line_kind,
        case when p_line_kind = 'presentation' then p_target_id else null end,
        case when p_line_kind = 'package' then p_target_id else null end,
        v_final_quantity,
        v_catalog_updated_at,
        'valid',
        v_now
      );
    else
      update public.cart_lines
      set
        quantity = v_final_quantity,
        catalog_updated_at_seen = v_catalog_updated_at,
        validation_status = 'valid',
        last_validated_at = v_now,
        updated_at = v_now
      where public.cart_lines.id = v_line_id;
    end if;
  end if;

  update public.carts
  set
    status = 'active',
    last_meaningful_activity_at = v_now,
    expires_at = v_now + interval '60 days',
    updated_at = v_now
  where public.carts.id = v_cart_id;

  return pg_catalog.jsonb_build_object(
    'cart_id', v_cart_id,
    'line_id', v_line_id,
    'line_kind', p_line_kind,
    'target_id', p_target_id,
    'quantity', v_final_quantity
  );
end;
$$;

revoke all on function private.set_authenticated_cart_item(text, uuid, integer, text) from PUBLIC;
revoke all on function private.set_authenticated_cart_item(text, uuid, integer, text) from anon;
revoke all on function private.set_authenticated_cart_item(text, uuid, integer, text) from authenticated;
grant execute on function private.set_authenticated_cart_item(text, uuid, integer, text) to authenticated;

create function public.set_authenticated_cart_item(
  p_line_kind text,
  p_target_id uuid,
  p_quantity integer,
  p_mode text default 'set'
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.set_authenticated_cart_item(
    p_line_kind,
    p_target_id,
    p_quantity,
    p_mode
  )
$$;

revoke all on function public.set_authenticated_cart_item(text, uuid, integer, text) from PUBLIC;
revoke all on function public.set_authenticated_cart_item(text, uuid, integer, text) from anon;
revoke all on function public.set_authenticated_cart_item(text, uuid, integer, text) from authenticated;
grant execute on function public.set_authenticated_cart_item(text, uuid, integer, text) to authenticated;

create function private.merge_guest_cart(
  p_operation_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_personal_account_id uuid;
  v_cart_id uuid;
  v_existing_result jsonb;
  v_result jsonb;
  v_accepted jsonb := '[]'::jsonb;
  v_rejected jsonb := '[]'::jsonb;
  v_item record;
  v_line_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if p_operation_id is null then
    raise exception 'Merge operation identifier is required';
  end if;

  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'Cart items must be a JSON array';
  end if;

  v_personal_account_id := private.current_personal_account_id();

  if v_personal_account_id is null then
    raise exception 'An active Personal Account is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_personal_account_id::text || ':' || p_operation_id::text,
      2
    )
  );

  select private.cart_merge_operations.result
  into v_existing_result
  from private.cart_merge_operations
  where private.cart_merge_operations.operation_id = p_operation_id
    and private.cart_merge_operations.personal_account_id = v_personal_account_id;

  if found then
    return v_existing_result;
  end if;

  if exists (
    select 1
    from private.cart_merge_operations
    where private.cart_merge_operations.operation_id = p_operation_id
  ) then
    raise exception 'Merge operation identifier already belongs to another account';
  end if;

  v_cart_id := private.get_or_create_current_cart();

  for v_item in
    select
      item.line_kind,
      item.target_id,
      pg_catalog.sum(item.quantity)::integer as quantity
    from pg_catalog.jsonb_to_recordset(p_items) as item(
      line_kind text,
      target_id uuid,
      quantity integer
    )
    group by item.line_kind, item.target_id
    order by item.line_kind, item.target_id
  loop
    begin
      if v_item.quantity is null or v_item.quantity <= 0 then
        raise exception 'Quantity must be positive';
      end if;

      v_line_result := private.set_authenticated_cart_item(
        v_item.line_kind,
        v_item.target_id,
        v_item.quantity,
        'add'
      );

      v_accepted := v_accepted || pg_catalog.jsonb_build_array(v_line_result);
    exception
      when others then
        v_rejected := v_rejected || pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'line_kind', v_item.line_kind,
            'target_id', v_item.target_id,
            'quantity', v_item.quantity,
            'reason', sqlerrm
          )
        );
    end;
  end loop;

  v_result := pg_catalog.jsonb_build_object(
    'operation_id', p_operation_id,
    'cart_id', v_cart_id,
    'accepted', v_accepted,
    'rejected', v_rejected
  );

  insert into private.cart_merge_operations (
    operation_id,
    personal_account_id,
    cart_id,
    result
  )
  values (
    p_operation_id,
    v_personal_account_id,
    v_cart_id,
    v_result
  );

  return v_result;
end;
$$;

revoke all on function private.merge_guest_cart(uuid, jsonb) from PUBLIC;
revoke all on function private.merge_guest_cart(uuid, jsonb) from anon;
revoke all on function private.merge_guest_cart(uuid, jsonb) from authenticated;
grant execute on function private.merge_guest_cart(uuid, jsonb) to authenticated;

create function public.merge_guest_cart(
  p_operation_id uuid,
  p_items jsonb
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.merge_guest_cart(p_operation_id, p_items)
$$;

revoke all on function public.merge_guest_cart(uuid, jsonb) from PUBLIC;
revoke all on function public.merge_guest_cart(uuid, jsonb) from anon;
revoke all on function public.merge_guest_cart(uuid, jsonb) from authenticated;
grant execute on function public.merge_guest_cart(uuid, jsonb) to authenticated;

create function private.create_order(
  p_customer_id uuid,
  p_cart_id uuid,
  p_items jsonb,
  p_destination jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_order_id uuid := pg_catalog.gen_random_uuid();
  v_order_number text;
  v_order_item_id uuid;
  v_line record;
  v_line_number integer := 0;
  v_name text;
  v_sku text;
  v_currency_code char(3);
  v_order_currency_code char(3);
  v_unit_price bigint;
  v_subtotal bigint;
  v_total bigint := 0;
  v_available bigint;
  v_component_count integer;
  v_valid_component_count integer;
  v_now timestamptz := pg_catalog.now();
  v_recipient_name text := nullif(pg_catalog.btrim(p_destination ->> 'recipient_name'), '');
  v_contact_phone text := nullif(pg_catalog.btrim(p_destination ->> 'contact_phone'), '');
  v_contact_email text := nullif(pg_catalog.btrim(p_destination ->> 'contact_email'), '');
  v_line_1 text := nullif(pg_catalog.btrim(p_destination ->> 'line_1'), '');
  v_city text := nullif(pg_catalog.btrim(p_destination ->> 'city'), '');
  v_region text := nullif(pg_catalog.btrim(p_destination ->> 'region'), '');
  v_postal_code text := nullif(pg_catalog.btrim(p_destination ->> 'postal_code'), '');
  v_country_code text := pg_catalog.upper(nullif(pg_catalog.btrim(p_destination ->> 'country_code'), ''));
begin
  if p_customer_id is null then
    raise exception 'Customer is required';
  end if;

  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array'
    or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'At least one order item is required';
  end if;

  if v_recipient_name is null
    or v_line_1 is null
    or v_city is null
    or v_region is null
    or v_postal_code is null
    or v_country_code is null then
    raise exception 'Destination is incomplete';
  end if;

  if pg_catalog.char_length(v_country_code) <> 2 then
    raise exception 'Country code must contain two letters';
  end if;

  if v_contact_phone is null and v_contact_email is null then
    raise exception 'A contact phone or email is required';
  end if;

  v_order_number := 'CM-' || pg_catalog.to_char(v_now, 'YYYYMMDD') || '-' ||
    pg_catalog.upper(pg_catalog.substr(pg_catalog.replace(v_order_id::text, '-', ''), 1, 10));

  insert into public.orders (
    id,
    order_number,
    customer_id,
    commercial_status,
    currency_code,
    subtotal_amount_minor,
    discount_amount_minor,
    tax_amount_minor,
    delivery_amount_minor,
    total_amount_minor,
    placed_at
  )
  values (
    v_order_id,
    v_order_number,
    p_customer_id,
    'pending_confirmation',
    'MXN',
    0,
    0,
    0,
    0,
    0,
    v_now
  );

  for v_line in
    select
      item.line_kind,
      item.target_id,
      pg_catalog.sum(item.quantity)::integer as quantity
    from pg_catalog.jsonb_to_recordset(p_items) as item(
      line_kind text,
      target_id uuid,
      quantity integer
    )
    group by item.line_kind, item.target_id
    order by item.line_kind, item.target_id
  loop
    if v_line.line_kind not in ('presentation', 'package') then
      raise exception 'Unsupported order item kind';
    end if;

    if v_line.target_id is null
      or v_line.quantity is null
      or v_line.quantity <= 0
      or v_line.quantity > 99 then
      raise exception 'Order item quantity must be between 1 and 99';
    end if;

    v_line_number := v_line_number + 1;
    v_order_item_id := pg_catalog.gen_random_uuid();

    if v_line.line_kind = 'presentation' then
      select
        case
          when nullif(pg_catalog.btrim(public.sellable_presentations.variant_label), '') is null
            then public.products.name
          else public.products.name || ' - ' || public.sellable_presentations.variant_label
        end,
        public.sellable_presentations.sku,
        public.sellable_presentations.currency_code,
        public.sellable_presentations.current_price_amount_minor,
        coalesce(public.presentation_inventory.on_hand_quantity, 0)
      into
        v_name,
        v_sku,
        v_currency_code,
        v_unit_price,
        v_available
      from public.sellable_presentations
      join public.products
        on public.products.id = public.sellable_presentations.product_id
      left join public.presentation_inventory
        on public.presentation_inventory.presentation_id = public.sellable_presentations.id
      where public.sellable_presentations.id = v_line.target_id
        and public.sellable_presentations.is_active = true
        and public.sellable_presentations.archived_at is null
        and public.products.is_active = true
        and public.products.archived_at is null
      for share of sellable_presentations, products;

      if not found then
        raise exception 'Presentation is not currently sellable';
      end if;

      if v_available < v_line.quantity then
        raise exception 'Presentation has insufficient availability';
      end if;

      v_subtotal := v_unit_price * v_line.quantity;

      insert into public.order_items (
        id,
        order_id,
        line_number,
        item_kind,
        presentation_id,
        package_id,
        quantity,
        historical_name,
        historical_sku,
        unit_price_amount_minor,
        subtotal_amount_minor,
        discount_amount_minor,
        tax_amount_minor,
        total_amount_minor,
        currency_code
      )
      values (
        v_order_item_id,
        v_order_id,
        v_line_number,
        'presentation',
        v_line.target_id,
        null,
        v_line.quantity,
        v_name,
        v_sku,
        v_unit_price,
        v_subtotal,
        0,
        0,
        v_subtotal,
        v_currency_code
      );
    else
      select
        public.packages.name,
        public.packages.currency_code,
        public.packages.current_price_amount_minor
      into
        v_name,
        v_currency_code,
        v_unit_price
      from public.packages
      where public.packages.id = v_line.target_id
        and public.packages.is_active = true
        and public.packages.archived_at is null
        and (public.packages.valid_from is null or public.packages.valid_from <= v_now)
        and (public.packages.valid_until is null or public.packages.valid_until > v_now)
      for share;

      if not found then
        raise exception 'Package is not currently sellable';
      end if;

      select
        pg_catalog.count(public.package_components.id)::integer,
        pg_catalog.count(public.package_components.id) filter (
          where public.sellable_presentations.is_active = true
            and public.sellable_presentations.archived_at is null
            and public.products.is_active = true
            and public.products.archived_at is null
        )::integer,
        pg_catalog.min(
          pg_catalog.floor(
            coalesce(public.presentation_inventory.on_hand_quantity, 0)::numeric /
            public.package_components.quantity
          )
        ) filter (
          where public.sellable_presentations.is_active = true
            and public.sellable_presentations.archived_at is null
            and public.products.is_active = true
            and public.products.archived_at is null
        )::bigint
      into v_component_count, v_valid_component_count, v_available
      from public.package_components
      left join public.sellable_presentations
        on public.sellable_presentations.id = public.package_components.presentation_id
      left join public.products
        on public.products.id = public.sellable_presentations.product_id
      left join public.presentation_inventory
        on public.presentation_inventory.presentation_id = public.sellable_presentations.id
      where public.package_components.package_id = v_line.target_id
        and public.package_components.is_active = true;

      if v_component_count = 0 or v_component_count <> v_valid_component_count then
        raise exception 'Package has no valid active components';
      end if;

      if v_available < v_line.quantity then
        raise exception 'Package has insufficient availability';
      end if;

      v_subtotal := v_unit_price * v_line.quantity;

      insert into public.order_items (
        id,
        order_id,
        line_number,
        item_kind,
        presentation_id,
        package_id,
        quantity,
        historical_name,
        historical_sku,
        unit_price_amount_minor,
        subtotal_amount_minor,
        discount_amount_minor,
        tax_amount_minor,
        total_amount_minor,
        currency_code
      )
      values (
        v_order_item_id,
        v_order_id,
        v_line_number,
        'package',
        null,
        v_line.target_id,
        v_line.quantity,
        v_name,
        null,
        v_unit_price,
        v_subtotal,
        0,
        0,
        v_subtotal,
        v_currency_code
      );

      insert into public.order_item_package_components (
        id,
        order_item_id,
        presentation_id,
        historical_product_name,
        historical_presentation_label,
        historical_sku,
        quantity_per_package,
        total_component_quantity
      )
      select
        pg_catalog.gen_random_uuid(),
        v_order_item_id,
        public.sellable_presentations.id,
        public.products.name,
        public.sellable_presentations.variant_label,
        public.sellable_presentations.sku,
        public.package_components.quantity,
        public.package_components.quantity * v_line.quantity
      from public.package_components
      join public.sellable_presentations
        on public.sellable_presentations.id = public.package_components.presentation_id
      join public.products
        on public.products.id = public.sellable_presentations.product_id
      where public.package_components.package_id = v_line.target_id
        and public.package_components.is_active = true
      order by public.sellable_presentations.id;
    end if;

    if v_order_currency_code is null then
      v_order_currency_code := v_currency_code;
    elsif v_order_currency_code <> v_currency_code then
      raise exception 'All order items must use the same currency';
    end if;

    v_total := v_total + v_subtotal;
  end loop;

  if v_line_number = 0 then
    raise exception 'At least one valid order item is required';
  end if;

  update public.orders
  set
    currency_code = v_order_currency_code,
    subtotal_amount_minor = v_total,
    total_amount_minor = v_total,
    updated_at = v_now
  where public.orders.id = v_order_id;

  insert into public.order_destinations (
    id,
    order_id,
    version_number,
    is_current,
    recipient_name,
    reception_kind,
    contact_phone,
    contact_email,
    line_1,
    line_2,
    neighborhood,
    city,
    region,
    postal_code,
    country_code,
    delivery_instructions,
    authorized_at
  )
  values (
    pg_catalog.gen_random_uuid(),
    v_order_id,
    1,
    true,
    v_recipient_name,
    null,
    v_contact_phone,
    v_contact_email,
    v_line_1,
    nullif(pg_catalog.btrim(p_destination ->> 'line_2'), ''),
    nullif(pg_catalog.btrim(p_destination ->> 'neighborhood'), ''),
    v_city,
    v_region,
    v_postal_code,
    v_country_code,
    nullif(pg_catalog.btrim(p_destination ->> 'delivery_instructions'), ''),
    v_now
  );

  if p_cart_id is not null then
    update public.carts
    set
      status = 'converted',
      converted_order_id = v_order_id,
      updated_at = v_now
    where public.carts.id = p_cart_id;

    if not found then
      raise exception 'Authenticated cart could not be converted';
    end if;
  end if;

  return pg_catalog.jsonb_build_object(
    'order_id', v_order_id,
    'order_number', v_order_number,
    'currency_code', v_order_currency_code,
    'total_amount_minor', v_total,
    'commercial_status', 'pending_confirmation'
  );
end;
$$;

revoke all on function private.create_order(uuid, uuid, jsonb, jsonb) from PUBLIC;
revoke all on function private.create_order(uuid, uuid, jsonb, jsonb) from anon;
revoke all on function private.create_order(uuid, uuid, jsonb, jsonb) from authenticated;

create function private.place_authenticated_order(
  p_cart_id uuid,
  p_destination jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_personal_account_id uuid;
  v_customer_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  v_personal_account_id := private.current_personal_account_id();

  if v_personal_account_id is null then
    raise exception 'An active Personal Account is required';
  end if;

  select public.personal_accounts.customer_id
  into v_customer_id
  from public.personal_accounts
  where public.personal_accounts.id = v_personal_account_id;

  perform 1
  from public.carts
  where public.carts.id = p_cart_id
    and public.carts.personal_account_id = v_personal_account_id
    and public.carts.status in ('active', 'inactive')
    and public.carts.expires_at > pg_catalog.now()
  for update;

  if not found then
    raise exception 'Cart is not current or does not belong to this account';
  end if;

  select pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'line_kind', public.cart_lines.line_kind,
      'target_id', case
        when public.cart_lines.line_kind = 'presentation'
          then public.cart_lines.presentation_id
        else public.cart_lines.package_id
      end,
      'quantity', public.cart_lines.quantity
    )
    order by public.cart_lines.created_at, public.cart_lines.id
  )
  into v_items
  from public.cart_lines
  where public.cart_lines.cart_id = p_cart_id;

  return private.create_order(
    v_customer_id,
    p_cart_id,
    v_items,
    p_destination
  );
end;
$$;

revoke all on function private.place_authenticated_order(uuid, jsonb) from PUBLIC;
revoke all on function private.place_authenticated_order(uuid, jsonb) from anon;
revoke all on function private.place_authenticated_order(uuid, jsonb) from authenticated;
grant execute on function private.place_authenticated_order(uuid, jsonb) to authenticated;

create function public.place_authenticated_order(
  p_cart_id uuid,
  p_destination jsonb
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.place_authenticated_order(p_cart_id, p_destination)
$$;

revoke all on function public.place_authenticated_order(uuid, jsonb) from PUBLIC;
revoke all on function public.place_authenticated_order(uuid, jsonb) from anon;
revoke all on function public.place_authenticated_order(uuid, jsonb) from authenticated;
grant execute on function public.place_authenticated_order(uuid, jsonb) to authenticated;

create function private.place_guest_order(
  p_items jsonb,
  p_destination jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_customer_id uuid;
begin
  if auth.uid() is not null then
    raise exception 'Signed-in customers must use authenticated checkout';
  end if;

  if nullif(pg_catalog.btrim(p_destination ->> 'recipient_name'), '') is null then
    raise exception 'Recipient name is required';
  end if;

  if nullif(pg_catalog.btrim(p_destination ->> 'contact_email'), '') is null
    and nullif(pg_catalog.btrim(p_destination ->> 'contact_phone'), '') is null then
    raise exception 'A contact phone or email is required';
  end if;

  v_customer_id := pg_catalog.gen_random_uuid();

  insert into public.customers (
    id,
    preferred_name,
    contact_email,
    contact_phone,
    status
  )
  values (
    v_customer_id,
    nullif(pg_catalog.btrim(p_destination ->> 'recipient_name'), ''),
    nullif(pg_catalog.btrim(p_destination ->> 'contact_email'), ''),
    nullif(pg_catalog.btrim(p_destination ->> 'contact_phone'), ''),
    'active'
  );

  return private.create_order(
    v_customer_id,
    null,
    p_items,
    p_destination
  );
end;
$$;

revoke all on function private.place_guest_order(jsonb, jsonb) from PUBLIC;
revoke all on function private.place_guest_order(jsonb, jsonb) from anon;
revoke all on function private.place_guest_order(jsonb, jsonb) from authenticated;

grant usage on schema private to anon;
grant execute on function private.place_guest_order(jsonb, jsonb) to anon;

create function public.place_guest_order(
  p_items jsonb,
  p_destination jsonb
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.place_guest_order(p_items, p_destination)
$$;

revoke all on function public.place_guest_order(jsonb, jsonb) from PUBLIC;
revoke all on function public.place_guest_order(jsonb, jsonb) from anon;
revoke all on function public.place_guest_order(jsonb, jsonb) from authenticated;
grant execute on function public.place_guest_order(jsonb, jsonb) to anon;
