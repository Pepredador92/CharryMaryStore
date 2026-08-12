grant insert, update on table
  public.products,
  public.sellable_presentations,
  public.packages,
  public.commercial_classifications
to authenticated;

grant insert, update, delete on table
  public.package_components,
  public.catalog_classification_assignments,
  public.catalog_resources
to authenticated;

create policy pol_products__operational_insert
  on public.products
  for insert
  to authenticated
  with check ((select private.has_capability('catalog.manage')));

create policy pol_products__operational_update
  on public.products
  for update
  to authenticated
  using ((select private.has_capability('catalog.manage')))
  with check ((select private.has_capability('catalog.manage')));

create policy pol_sellable_presentations__operational_insert
  on public.sellable_presentations
  for insert
  to authenticated
  with check ((select private.has_capability('catalog.manage')));

create policy pol_sellable_presentations__operational_update
  on public.sellable_presentations
  for update
  to authenticated
  using ((select private.has_capability('catalog.manage')))
  with check ((select private.has_capability('catalog.manage')));

create policy pol_packages__operational_insert
  on public.packages
  for insert
  to authenticated
  with check ((select private.has_capability('catalog.manage')));

create policy pol_packages__operational_update
  on public.packages
  for update
  to authenticated
  using ((select private.has_capability('catalog.manage')))
  with check ((select private.has_capability('catalog.manage')));

create policy pol_package_components__operational_insert
  on public.package_components
  for insert
  to authenticated
  with check ((select private.has_capability('catalog.manage')));

create policy pol_package_components__operational_update
  on public.package_components
  for update
  to authenticated
  using ((select private.has_capability('catalog.manage')))
  with check ((select private.has_capability('catalog.manage')));

create policy pol_package_components__operational_delete
  on public.package_components
  for delete
  to authenticated
  using ((select private.has_capability('catalog.manage')));

create policy pol_commercial_classifications__operational_insert
  on public.commercial_classifications
  for insert
  to authenticated
  with check ((select private.has_capability('catalog.manage')));

create policy pol_commercial_classifications__operational_update
  on public.commercial_classifications
  for update
  to authenticated
  using ((select private.has_capability('catalog.manage')))
  with check ((select private.has_capability('catalog.manage')));

create policy pol_catalog_classification_assignments__operational_insert
  on public.catalog_classification_assignments
  for insert
  to authenticated
  with check ((select private.has_capability('catalog.manage')));

create policy pol_catalog_classification_assignments__operational_delete
  on public.catalog_classification_assignments
  for delete
  to authenticated
  using ((select private.has_capability('catalog.manage')));

create policy pol_catalog_resources__operational_insert
  on public.catalog_resources
  for insert
  to authenticated
  with check ((select private.has_capability('catalog.manage')));

create policy pol_catalog_resources__operational_update
  on public.catalog_resources
  for update
  to authenticated
  using ((select private.has_capability('catalog.manage')))
  with check ((select private.has_capability('catalog.manage')));

create policy pol_catalog_resources__operational_delete
  on public.catalog_resources
  for delete
  to authenticated
  using ((select private.has_capability('catalog.manage')));

create function public.current_operational_capabilities()
returns table (code text)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select public.capabilities.code
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
  order by public.capabilities.code
$$;

revoke all on function public.current_operational_capabilities() from PUBLIC;
revoke all on function public.current_operational_capabilities() from anon;
revoke all on function public.current_operational_capabilities() from authenticated;
grant execute on function public.current_operational_capabilities() to authenticated;

create function public.adjust_presentation_inventory(
  p_presentation_id uuid,
  p_quantity_delta bigint,
  p_movement_kind text,
  p_cause text
)
returns table (
  presentation_id uuid,
  on_hand_quantity bigint,
  movement_id uuid
)
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_operational_person_id uuid;
  v_current_quantity bigint;
  v_new_quantity bigint;
  v_movement_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if not private.has_capability('inventory.adjust') then
    raise exception 'Missing inventory.adjust capability';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Quantity delta must be nonzero';
  end if;

  if p_movement_kind not in ('stock_entry', 'manual_adjustment') then
    raise exception 'Movement kind is not allowed for manual inventory operations';
  end if;

  if p_movement_kind = 'stock_entry' and p_quantity_delta < 0 then
    raise exception 'Stock entry quantity must be positive';
  end if;

  if nullif(pg_catalog.btrim(p_cause), '') is null then
    raise exception 'Cause is required';
  end if;

  perform 1
  from public.sellable_presentations
  where public.sellable_presentations.id = p_presentation_id
  for update;

  if not found then
    raise exception 'Sellable presentation does not exist';
  end if;

  select public.presentation_inventory.on_hand_quantity
  into v_current_quantity
  from public.presentation_inventory
  where public.presentation_inventory.presentation_id = p_presentation_id
  for update;

  if not found then
    v_current_quantity := 0;
  end if;

  v_new_quantity := v_current_quantity + p_quantity_delta;

  if v_new_quantity < 0 then
    raise exception 'Inventory cannot become negative';
  end if;

  insert into public.presentation_inventory (
    presentation_id,
    on_hand_quantity,
    updated_at
  )
  values (
    p_presentation_id,
    v_new_quantity,
    pg_catalog.now()
  )
  on conflict (presentation_id) do update
  set
    on_hand_quantity = excluded.on_hand_quantity,
    updated_at = excluded.updated_at;

  v_actor_operational_person_id := private.current_operational_person_id();
  v_movement_id := pg_catalog.gen_random_uuid();

  insert into public.inventory_movements (
    id,
    presentation_id,
    quantity_delta,
    movement_kind,
    order_id,
    actor_operational_person_id,
    cause,
    occurred_at
  )
  values (
    v_movement_id,
    p_presentation_id,
    p_quantity_delta,
    p_movement_kind,
    null,
    v_actor_operational_person_id,
    pg_catalog.btrim(p_cause),
    pg_catalog.now()
  );

  return query
  select p_presentation_id, v_new_quantity, v_movement_id;
end;
$$;

revoke all on function public.adjust_presentation_inventory(uuid, bigint, text, text) from PUBLIC;
revoke all on function public.adjust_presentation_inventory(uuid, bigint, text, text) from anon;
revoke all on function public.adjust_presentation_inventory(uuid, bigint, text, text) from authenticated;
grant execute on function public.adjust_presentation_inventory(uuid, bigint, text, text) to authenticated;

create function public.set_primary_catalog_resource(p_resource_id uuid)
returns public.catalog_resources
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_resource public.catalog_resources%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if not private.has_capability('catalog.manage') then
    raise exception 'Missing catalog.manage capability';
  end if;

  select public.catalog_resources.*
  into v_resource
  from public.catalog_resources
  where public.catalog_resources.id = p_resource_id
  for update;

  if not found then
    raise exception 'Catalog resource does not exist';
  end if;

  update public.catalog_resources
  set
    is_primary = (public.catalog_resources.id = p_resource_id),
    updated_at = pg_catalog.now()
  where
    (v_resource.product_id is not null and public.catalog_resources.product_id = v_resource.product_id)
    or (v_resource.presentation_id is not null and public.catalog_resources.presentation_id = v_resource.presentation_id)
    or (v_resource.package_id is not null and public.catalog_resources.package_id = v_resource.package_id);

  select public.catalog_resources.*
  into v_resource
  from public.catalog_resources
  where public.catalog_resources.id = p_resource_id;

  return v_resource;
end;
$$;

revoke all on function public.set_primary_catalog_resource(uuid) from PUBLIC;
revoke all on function public.set_primary_catalog_resource(uuid) from anon;
revoke all on function public.set_primary_catalog_resource(uuid) from authenticated;
grant execute on function public.set_primary_catalog_resource(uuid) to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'catalog-resources',
  'catalog-resources',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']::text[]
)
on conflict (id) do nothing;

create policy pol_storage_objects__catalog_public_select
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'catalog-resources');

create policy pol_storage_objects__catalog_operational_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'catalog-resources'
    and (select private.has_capability('catalog.manage'))
  );

create policy pol_storage_objects__catalog_operational_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'catalog-resources'
    and (select private.has_capability('catalog.manage'))
  )
  with check (
    bucket_id = 'catalog-resources'
    and (select private.has_capability('catalog.manage'))
  );

create policy pol_storage_objects__catalog_operational_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'catalog-resources'
    and (select private.has_capability('catalog.manage'))
  );
