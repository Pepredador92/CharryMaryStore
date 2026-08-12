create index ix_cart_merge_operations__personal_account_id
  on private.cart_merge_operations (personal_account_id);

create index ix_cart_merge_operations__cart_id
  on private.cart_merge_operations (cart_id);

drop policy pol_presentation_inventory__public_select
  on public.presentation_inventory;

drop policy pol_presentation_inventory__operational_select
  on public.presentation_inventory;

create policy pol_presentation_inventory__public_select
  on public.presentation_inventory
  for select
  to anon
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

create policy pol_presentation_inventory__authenticated_select
  on public.presentation_inventory
  for select
  to authenticated
  using (
    (
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
    )
    or (select private.has_capability('inventory.read'))
    or (select private.has_capability('inventory.adjust'))
  );
