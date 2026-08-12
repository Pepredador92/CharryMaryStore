revoke all privileges on table
  public.products,
  public.sellable_presentations,
  public.presentation_inventory,
  public.packages,
  public.package_components,
  public.commercial_classifications,
  public.catalog_classification_assignments,
  public.catalog_resources,
  public.operational_people,
  public.operational_accounts,
  public.capabilities,
  public.operational_account_capabilities,
  public.customers,
  public.personal_accounts,
  public.customer_addresses,
  public.carts,
  public.cart_lines,
  public.orders,
  public.order_destinations,
  public.order_items,
  public.order_item_package_components,
  public.order_actions,
  public.inventory_movements,
  public.preparations,
  public.preparation_actions,
  public.preparation_item_verifications,
  public.logistics_providers,
  public.deliveries,
  public.delivery_assignments,
  public.delivery_custody_events,
  public.delivery_attempts,
  public.delivery_actions,
  public.delivery_evidence_items,
  public.support_requests,
  public.support_messages,
  public.audit_events
from anon, authenticated;

grant select on table
  public.products,
  public.sellable_presentations,
  public.packages,
  public.package_components,
  public.commercial_classifications,
  public.catalog_classification_assignments,
  public.catalog_resources
to anon;

grant select on table
  public.products,
  public.sellable_presentations,
  public.presentation_inventory,
  public.packages,
  public.package_components,
  public.commercial_classifications,
  public.catalog_classification_assignments,
  public.catalog_resources,
  public.operational_people,
  public.operational_accounts,
  public.capabilities,
  public.operational_account_capabilities,
  public.customers,
  public.personal_accounts,
  public.customer_addresses,
  public.carts,
  public.cart_lines,
  public.orders,
  public.order_destinations,
  public.order_items,
  public.order_item_package_components,
  public.order_actions,
  public.inventory_movements,
  public.preparations,
  public.preparation_actions,
  public.preparation_item_verifications,
  public.logistics_providers,
  public.deliveries,
  public.delivery_assignments,
  public.delivery_custody_events,
  public.delivery_attempts,
  public.delivery_actions,
  public.audit_events
to authenticated;

grant insert (
  id,
  customer_id,
  label,
  recipient_name,
  contact_phone,
  line_1,
  line_2,
  neighborhood,
  city,
  region,
  postal_code,
  country_code,
  delivery_instructions,
  is_active
) on table public.customer_addresses to authenticated;

grant update (
  label,
  recipient_name,
  contact_phone,
  line_1,
  line_2,
  neighborhood,
  city,
  region,
  postal_code,
  country_code,
  delivery_instructions,
  is_active,
  updated_at
) on table public.customer_addresses to authenticated;

create policy pol_products__public_select
  on public.products
  for select
  to anon, authenticated
  using (
    is_active = true
    and archived_at is null
  );

create policy pol_products__operational_select
  on public.products
  for select
  to authenticated
  using (
    private.has_capability('catalog.read')
    or private.has_capability('catalog.manage')
  );

create policy pol_sellable_presentations__public_select
  on public.sellable_presentations
  for select
  to anon, authenticated
  using (
    is_active = true
    and archived_at is null
    and exists (
      select 1
      from public.products
      where public.products.id = public.sellable_presentations.product_id
        and public.products.is_active = true
        and public.products.archived_at is null
    )
  );

create policy pol_sellable_presentations__operational_select
  on public.sellable_presentations
  for select
  to authenticated
  using (
    private.has_capability('catalog.read')
    or private.has_capability('catalog.manage')
  );

create policy pol_presentation_inventory__operational_select
  on public.presentation_inventory
  for select
  to authenticated
  using (
    private.has_capability('inventory.read')
    or private.has_capability('inventory.adjust')
  );

create policy pol_packages__public_select
  on public.packages
  for select
  to anon, authenticated
  using (
    is_active = true
    and archived_at is null
    and (valid_from is null or valid_from <= now())
    and (valid_until is null or valid_until > now())
  );

create policy pol_packages__operational_select
  on public.packages
  for select
  to authenticated
  using (
    private.has_capability('catalog.read')
    or private.has_capability('catalog.manage')
  );

create policy pol_package_components__public_select
  on public.package_components
  for select
  to anon, authenticated
  using (
    is_active = true
    and exists (
      select 1
      from public.packages
      where public.packages.id = public.package_components.package_id
        and public.packages.is_active = true
        and public.packages.archived_at is null
        and (public.packages.valid_from is null or public.packages.valid_from <= now())
        and (public.packages.valid_until is null or public.packages.valid_until > now())
    )
    and exists (
      select 1
      from public.sellable_presentations
      join public.products
        on public.products.id = public.sellable_presentations.product_id
      where public.sellable_presentations.id = public.package_components.presentation_id
        and public.sellable_presentations.is_active = true
        and public.sellable_presentations.archived_at is null
        and public.products.is_active = true
        and public.products.archived_at is null
    )
  );

create policy pol_package_components__operational_select
  on public.package_components
  for select
  to authenticated
  using (
    private.has_capability('catalog.read')
    or private.has_capability('catalog.manage')
  );

create policy pol_commercial_classifications__public_select
  on public.commercial_classifications
  for select
  to anon, authenticated
  using (
    is_active = true
  );

create policy pol_commercial_classifications__operational_select
  on public.commercial_classifications
  for select
  to authenticated
  using (
    private.has_capability('catalog.read')
    or private.has_capability('catalog.manage')
  );

create policy pol_catalog_classification_assignments__public_select
  on public.catalog_classification_assignments
  for select
  to anon, authenticated
  using (
    exists (
      select 1
      from public.commercial_classifications
      where public.commercial_classifications.id = public.catalog_classification_assignments.classification_id
        and public.commercial_classifications.is_active = true
    )
    and (
      (
        product_id is not null
        and exists (
          select 1
          from public.products
          where public.products.id = public.catalog_classification_assignments.product_id
            and public.products.is_active = true
            and public.products.archived_at is null
        )
      )
      or (
        package_id is not null
        and exists (
          select 1
          from public.packages
          where public.packages.id = public.catalog_classification_assignments.package_id
            and public.packages.is_active = true
            and public.packages.archived_at is null
            and (public.packages.valid_from is null or public.packages.valid_from <= now())
            and (public.packages.valid_until is null or public.packages.valid_until > now())
        )
      )
    )
  );

create policy pol_catalog_classification_assignments__operational_select
  on public.catalog_classification_assignments
  for select
  to authenticated
  using (
    private.has_capability('catalog.read')
    or private.has_capability('catalog.manage')
  );

create policy pol_catalog_resources__public_select
  on public.catalog_resources
  for select
  to anon, authenticated
  using (
    is_active = true
    and (
      (
        product_id is not null
        and exists (
          select 1
          from public.products
          where public.products.id = public.catalog_resources.product_id
            and public.products.is_active = true
            and public.products.archived_at is null
        )
      )
      or (
        presentation_id is not null
        and exists (
          select 1
          from public.sellable_presentations
          join public.products
            on public.products.id = public.sellable_presentations.product_id
          where public.sellable_presentations.id = public.catalog_resources.presentation_id
            and public.sellable_presentations.is_active = true
            and public.sellable_presentations.archived_at is null
            and public.products.is_active = true
            and public.products.archived_at is null
        )
      )
      or (
        package_id is not null
        and exists (
          select 1
          from public.packages
          where public.packages.id = public.catalog_resources.package_id
            and public.packages.is_active = true
            and public.packages.archived_at is null
            and (public.packages.valid_from is null or public.packages.valid_from <= now())
            and (public.packages.valid_until is null or public.packages.valid_until > now())
        )
      )
    )
  );

create policy pol_catalog_resources__operational_select
  on public.catalog_resources
  for select
  to authenticated
  using (
    private.has_capability('catalog.read')
    or private.has_capability('catalog.manage')
  );

create policy pol_operational_people__own_select
  on public.operational_people
  for select
  to authenticated
  using (
    id = private.current_operational_person_id()
  );

create policy pol_operational_people__operational_select
  on public.operational_people
  for select
  to authenticated
  using (
    private.has_capability('access.read')
    or private.has_capability('access.manage')
  );

create policy pol_operational_accounts__own_select
  on public.operational_accounts
  for select
  to authenticated
  using (
    id = private.current_operational_account_id()
  );

create policy pol_operational_accounts__operational_select
  on public.operational_accounts
  for select
  to authenticated
  using (
    private.has_capability('access.read')
    or private.has_capability('access.manage')
  );

create policy pol_capabilities__operational_select
  on public.capabilities
  for select
  to authenticated
  using (
    private.has_capability('access.read')
    or private.has_capability('access.manage')
  );

create policy pol_operational_account_capabilities__operational_select
  on public.operational_account_capabilities
  for select
  to authenticated
  using (
    private.has_capability('access.read')
    or private.has_capability('access.manage')
  );

create policy pol_customers__personal_select
  on public.customers
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.personal_accounts
      where public.personal_accounts.customer_id = public.customers.id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_personal_accounts__personal_select
  on public.personal_accounts
  for select
  to authenticated
  using (
    auth_user_id = (select auth.uid())
    and status = 'active'
  );

create policy pol_customer_addresses__personal_select
  on public.customer_addresses
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.personal_accounts
      where public.personal_accounts.customer_id = public.customer_addresses.customer_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_customer_addresses__personal_insert
  on public.customer_addresses
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.personal_accounts
      where public.personal_accounts.customer_id = public.customer_addresses.customer_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_customer_addresses__personal_update
  on public.customer_addresses
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.personal_accounts
      where public.personal_accounts.customer_id = public.customer_addresses.customer_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  )
  with check (
    exists (
      select 1
      from public.personal_accounts
      where public.personal_accounts.customer_id = public.customer_addresses.customer_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_carts__personal_select
  on public.carts
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.personal_accounts
      where public.personal_accounts.id = public.carts.personal_account_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_cart_lines__personal_select
  on public.cart_lines
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.carts
      join public.personal_accounts
        on public.personal_accounts.id = public.carts.personal_account_id
      where public.carts.id = public.cart_lines.cart_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_orders__personal_select
  on public.orders
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.personal_accounts
      where public.personal_accounts.customer_id = public.orders.customer_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_orders__operational_select
  on public.orders
  for select
  to authenticated
  using (
    private.has_capability('orders.read')
    or private.has_capability('orders.manage')
  );

create policy pol_order_destinations__personal_select
  on public.order_destinations
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.orders
      join public.personal_accounts
        on public.personal_accounts.customer_id = public.orders.customer_id
      where public.orders.id = public.order_destinations.order_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_order_destinations__operational_select
  on public.order_destinations
  for select
  to authenticated
  using (
    private.has_capability('orders.read')
    or private.has_capability('orders.manage')
  );

create policy pol_order_items__personal_select
  on public.order_items
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.orders
      join public.personal_accounts
        on public.personal_accounts.customer_id = public.orders.customer_id
      where public.orders.id = public.order_items.order_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_order_items__operational_select
  on public.order_items
  for select
  to authenticated
  using (
    private.has_capability('orders.read')
    or private.has_capability('orders.manage')
    or private.has_capability('preparation.read')
    or private.has_capability('preparation.manage')
    or (
      private.has_capability('preparation.operate')
      and exists (
        select 1
        from public.preparations
        where public.preparations.order_id = public.order_items.order_id
          and public.preparations.current_responsible_person_id = private.current_operational_person_id()
      )
    )
  );

create policy pol_order_item_package_components__personal_select
  on public.order_item_package_components
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.order_items
      join public.orders
        on public.orders.id = public.order_items.order_id
      join public.personal_accounts
        on public.personal_accounts.customer_id = public.orders.customer_id
      where public.order_items.id = public.order_item_package_components.order_item_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_order_item_package_components__operational_select
  on public.order_item_package_components
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.order_items
      where public.order_items.id = public.order_item_package_components.order_item_id
        and (
          private.has_capability('orders.read')
          or private.has_capability('orders.manage')
          or private.has_capability('preparation.read')
          or private.has_capability('preparation.manage')
          or (
            private.has_capability('preparation.operate')
            and exists (
              select 1
              from public.preparations
              where public.preparations.order_id = public.order_items.order_id
                and public.preparations.current_responsible_person_id = private.current_operational_person_id()
            )
          )
        )
    )
  );

create policy pol_order_actions__operational_select
  on public.order_actions
  for select
  to authenticated
  using (
    private.has_capability('orders.read')
    or private.has_capability('orders.manage')
  );

create policy pol_inventory_movements__operational_select
  on public.inventory_movements
  for select
  to authenticated
  using (
    private.has_capability('inventory.read')
    or private.has_capability('inventory.adjust')
  );

create policy pol_preparations__operational_select
  on public.preparations
  for select
  to authenticated
  using (
    private.has_capability('preparation.read')
    or private.has_capability('preparation.manage')
    or (
      private.has_capability('preparation.operate')
      and current_responsible_person_id = private.current_operational_person_id()
    )
  );

create policy pol_preparation_actions__operational_select
  on public.preparation_actions
  for select
  to authenticated
  using (
    private.has_capability('preparation.read')
    or private.has_capability('preparation.manage')
    or (
      private.has_capability('preparation.operate')
      and exists (
        select 1
        from public.preparations
        where public.preparations.id = public.preparation_actions.preparation_id
          and public.preparations.current_responsible_person_id = private.current_operational_person_id()
      )
    )
  );

create policy pol_preparation_item_verifications__operational_select
  on public.preparation_item_verifications
  for select
  to authenticated
  using (
    private.has_capability('preparation.read')
    or private.has_capability('preparation.manage')
    or (
      private.has_capability('preparation.operate')
      and exists (
        select 1
        from public.preparations
        where public.preparations.id = public.preparation_item_verifications.preparation_id
          and public.preparations.current_responsible_person_id = private.current_operational_person_id()
      )
    )
  );

create policy pol_logistics_providers__operational_select
  on public.logistics_providers
  for select
  to authenticated
  using (
    private.has_capability('delivery.read')
    or private.has_capability('delivery.manage')
  );

create policy pol_deliveries__personal_select
  on public.deliveries
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.orders
      join public.personal_accounts
        on public.personal_accounts.customer_id = public.orders.customer_id
      where public.orders.id = public.deliveries.order_id
        and public.personal_accounts.auth_user_id = (select auth.uid())
        and public.personal_accounts.status = 'active'
    )
  );

create policy pol_deliveries__operational_select
  on public.deliveries
  for select
  to authenticated
  using (
    private.has_capability('delivery.read')
    or private.has_capability('delivery.manage')
    or (
      private.has_capability('delivery.operate')
      and exists (
        select 1
        from public.delivery_assignments
        where public.delivery_assignments.delivery_id = public.deliveries.id
          and public.delivery_assignments.operational_person_id = private.current_operational_person_id()
          and public.delivery_assignments.ended_at is null
      )
    )
  );

create policy pol_delivery_assignments__operational_select
  on public.delivery_assignments
  for select
  to authenticated
  using (
    private.has_capability('delivery.read')
    or private.has_capability('delivery.manage')
    or (
      private.has_capability('delivery.operate')
      and operational_person_id = private.current_operational_person_id()
    )
  );

create policy pol_delivery_custody_events__operational_select
  on public.delivery_custody_events
  for select
  to authenticated
  using (
    private.has_capability('delivery.read')
    or private.has_capability('delivery.manage')
    or (
      private.has_capability('delivery.operate')
      and exists (
        select 1
        from public.delivery_assignments
        where public.delivery_assignments.delivery_id = public.delivery_custody_events.delivery_id
          and public.delivery_assignments.operational_person_id = private.current_operational_person_id()
          and public.delivery_assignments.ended_at is null
      )
    )
  );

create policy pol_delivery_attempts__operational_select
  on public.delivery_attempts
  for select
  to authenticated
  using (
    private.has_capability('delivery.read')
    or private.has_capability('delivery.manage')
    or (
      private.has_capability('delivery.operate')
      and exists (
        select 1
        from public.delivery_assignments
        where public.delivery_assignments.delivery_id = public.delivery_attempts.delivery_id
          and public.delivery_assignments.operational_person_id = private.current_operational_person_id()
          and public.delivery_assignments.ended_at is null
      )
    )
  );

create policy pol_delivery_actions__operational_select
  on public.delivery_actions
  for select
  to authenticated
  using (
    private.has_capability('delivery.read')
    or private.has_capability('delivery.manage')
    or (
      private.has_capability('delivery.operate')
      and exists (
        select 1
        from public.delivery_assignments
        where public.delivery_assignments.delivery_id = public.delivery_actions.delivery_id
          and public.delivery_assignments.operational_person_id = private.current_operational_person_id()
          and public.delivery_assignments.ended_at is null
      )
    )
  );

create policy pol_audit_events__operational_select
  on public.audit_events
  for select
  to authenticated
  using (
    private.has_capability('audit.read')
  );
