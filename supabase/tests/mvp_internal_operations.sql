begin;

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if not coalesce(p_condition, false) then raise exception 'Assertion failed: %', p_message; end if;
end;
$$;

insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cm-imp04-operator@test.invalid', now(), now()),
  ('10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cm-imp04-no-capability@test.invalid', now(), now()),
  ('10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'cm-imp04-customer-a@test.invalid', now(), now()),
  ('10000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'cm-imp04-customer-b@test.invalid', now(), now());

insert into public.operational_people (id, internal_reference, display_name, status, started_at)
values
  ('20000000-0000-0000-0000-000000000001', 'CM-IMP04-OPERATOR', 'Operador temporal', 'active', now()),
  ('20000000-0000-0000-0000-000000000002', 'CM-IMP04-NO-CAP', 'Sin capacidades', 'active', now());

insert into public.operational_accounts (id, operational_person_id, auth_user_id, status, activated_at)
values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'active', now()),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'active', now());

insert into public.operational_account_capabilities (
  id, operational_account_id, capability_id, granted_by_person_id, granted_at, reason
)
select gen_random_uuid(), '30000000-0000-0000-0000-000000000001', id,
  '20000000-0000-0000-0000-000000000001', now(), 'CM-IMP-04 rollback test'
from public.capabilities where is_active;

insert into public.customers (id, preferred_name, contact_email, status)
values
  ('50000000-0000-0000-0000-000000000001', 'Cliente temporal', 'customer-a@test.invalid', 'active'),
  ('50000000-0000-0000-0000-000000000002', 'Cliente aislado', 'customer-b@test.invalid', 'active');

insert into public.personal_accounts (id, customer_id, auth_user_id, status)
values
  ('51000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'active'),
  ('51000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000004', 'active');

insert into public.products (id, name) values ('40000000-0000-0000-0000-000000000001', 'Producto temporal');
insert into public.sellable_presentations (
  id, product_id, sku, variant_label, current_price_amount_minor, currency_code, is_active
)
values
  ('41000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'CM-TEST-A', 'A', 500, 'MXN', true),
  ('41000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001', 'CM-TEST-B', 'B', 500, 'MXN', true);
insert into public.presentation_inventory (presentation_id, on_hand_quantity)
values
  ('41000000-0000-0000-0000-000000000001', 10),
  ('41000000-0000-0000-0000-000000000002', 10);
insert into public.packages (id, name, current_price_amount_minor, currency_code, is_active)
values ('42000000-0000-0000-0000-000000000001', 'Paquete temporal', 1000, 'MXN', true);

insert into public.orders (
  id, order_number, customer_id, commercial_status, currency_code,
  subtotal_amount_minor, discount_amount_minor, tax_amount_minor,
  delivery_amount_minor, total_amount_minor, placed_at
)
values
  ('60000000-0000-0000-0000-000000000001', 'CM-IMP04-001', '50000000-0000-0000-0000-000000000001', 'pending_confirmation', 'MXN', 2000, 0, 0, 0, 2000, now()),
  ('60000000-0000-0000-0000-000000000002', 'CM-IMP04-002', '50000000-0000-0000-0000-000000000001', 'pending_confirmation', 'MXN', 49500, 0, 0, 0, 49500, now()),
  ('60000000-0000-0000-0000-000000000003', 'CM-IMP04-003', '50000000-0000-0000-0000-000000000001', 'pending_confirmation', 'MXN', 500, 0, 0, 0, 500, now());

insert into public.order_destinations (
  id, order_id, version_number, is_current, recipient_name, line_1,
  city, region, postal_code, country_code, authorized_at
)
select gen_random_uuid(), id, 1, true, 'Recepción temporal', 'Calle de prueba 1',
  'Ciudad', 'Región', '00000', 'MX', placed_at
from public.orders where order_number like 'CM-IMP04-%';

insert into public.order_items (
  id, order_id, line_number, item_kind, presentation_id, package_id,
  quantity, historical_name, historical_sku, unit_price_amount_minor,
  subtotal_amount_minor, discount_amount_minor, tax_amount_minor,
  total_amount_minor, currency_code
)
values
  ('62000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 1, 'package', null, '42000000-0000-0000-0000-000000000001', 2, 'Paquete histórico', null, 1000, 2000, 0, 0, 2000, 'MXN'),
  ('62000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000002', 1, 'presentation', '41000000-0000-0000-0000-000000000001', null, 99, 'Presentación histórica', 'CM-TEST-A', 500, 49500, 0, 0, 49500, 'MXN'),
  ('62000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000003', 1, 'presentation', '41000000-0000-0000-0000-000000000001', null, 1, 'Presentación histórica', 'CM-TEST-A', 500, 500, 0, 0, 500, 'MXN');

insert into public.order_item_package_components (
  id, order_item_id, presentation_id, historical_product_name,
  historical_presentation_label, historical_sku, quantity_per_package,
  total_component_quantity
)
values
  (gen_random_uuid(), '62000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000001', 'Producto A', 'A', 'CM-TEST-A', 1, 2),
  (gen_random_uuid(), '62000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000002', 'Producto B', 'B', 'CM-TEST-B', 2, 4);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
do $$
declare v_rejected boolean := false;
begin
  begin perform public.manage_order('60000000-0000-0000-0000-000000000003', 'confirm', null); exception when others then v_rejected := true; end;
  perform pg_temp.assert_true(v_rejected, 'operator without capability must be rejected');
end;
$$;
reset role;
select pg_temp.assert_true((select commercial_status = 'pending_confirmation' from public.orders where id = '60000000-0000-0000-0000-000000000003'), 'unauthorized confirmation must not mutate order');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select public.manage_order('60000000-0000-0000-0000-000000000001', 'confirm', null);
select public.authorize_order_preparation('60000000-0000-0000-0000-000000000001');
select pg_temp.assert_true((select on_hand_quantity = 8 from public.presentation_inventory where presentation_id = '41000000-0000-0000-0000-000000000001'), 'first package component decrement');
select pg_temp.assert_true((select on_hand_quantity = 6 from public.presentation_inventory where presentation_id = '41000000-0000-0000-0000-000000000002'), 'second package component decrement');
select pg_temp.assert_true((select count(*) = 2 from public.inventory_movements where order_id = '60000000-0000-0000-0000-000000000001'), 'one movement per required presentation');

do $$
declare v_rejected boolean := false;
begin
  begin perform public.authorize_order_preparation('60000000-0000-0000-0000-000000000001'); exception when others then v_rejected := true; end;
  perform pg_temp.assert_true(v_rejected, 'double authorization must be rejected');
end;
$$;
select pg_temp.assert_true((select count(*) = 2 from public.inventory_movements where order_id = '60000000-0000-0000-0000-000000000001'), 'double authorization must not double-decrement');

select public.manage_order('60000000-0000-0000-0000-000000000002', 'confirm', null);
do $$
declare v_rejected boolean := false;
begin
  begin perform public.authorize_order_preparation('60000000-0000-0000-0000-000000000002'); exception when others then v_rejected := true; end;
  perform pg_temp.assert_true(v_rejected, 'insufficient inventory must be rejected');
  perform pg_temp.assert_true(not exists(select 1 from public.preparations where order_id = '60000000-0000-0000-0000-000000000002'), 'insufficient inventory must not create preparation');
end;
$$;

select public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'start', null, null);
do $$
declare v_rejected boolean := false;
begin
  begin perform public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'complete', null, null); exception when others then v_rejected := true; end;
  perform pg_temp.assert_true(v_rejected, 'completion without verification must be rejected');
end;
$$;
select public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'verify', '62000000-0000-0000-0000-000000000001', null);
select public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'complete', null, null);
select public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'reopen', null, 'Control de reapertura');
select public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'block', null, 'Control de bloqueo');
select public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'unblock', null, null);
select public.manage_preparation((select id from public.preparations where order_id = '60000000-0000-0000-0000-000000000001'), 'complete', null, null);

select public.create_order_delivery('60000000-0000-0000-0000-000000000001');
select public.assign_delivery((select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'), '20000000-0000-0000-0000-000000000001', null, null, 'responsible', 'Asignación de prueba');
select public.record_delivery_custody((select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'), 'accepted', 'cherry_mary', null, null, 'operational_person', '20000000-0000-0000-0000-000000000001', null, null, 'Custodia de prueba');
select public.set_delivery_state((select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'), 'start_transit', 'Salida de prueba');
select public.register_delivery_attempt((select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'), 'failed', 'Destino inaccesible', null, 'rollback_test', null);
select public.register_delivery_attempt((select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'), 'delivered', null, 'Recepción temporal confirmada', 'rollback_test', null);
select pg_temp.assert_true((select count(*) = 2 from public.delivery_attempts), 'multiple delivery attempts must be preserved');
select public.register_delivery_evidence(
  (select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'),
  (select id from public.delivery_attempts where result = 'delivered'),
  'Comprobar conclusión logística', 'receipt_metadata', 'sensitive_no_dispute',
  null, null, 'test-reference', 'text/plain', true, now() + interval '7 days', null
);
select pg_temp.assert_true((select jsonb_array_length(public.list_delivery_evidence((select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'))) = 1), 'evidence metadata must be visible through controlled RPC');
select public.delete_delivery_evidence(
  (public.list_delivery_evidence((select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001'))->0->>'id')::uuid,
  'Eliminación lógica de prueba'
);

do $$
declare v_rejected boolean := false; v_count integer := 0;
begin
  begin
    update public.inventory_movements set cause = 'mutación prohibida' where order_id = '60000000-0000-0000-0000-000000000001';
    get diagnostics v_count = row_count;
    v_rejected := v_count = 0;
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected, 'append-only movement update must be rejected');
  v_rejected := false;
  begin
    delete from public.delivery_attempts where delivery_id = (select id from public.deliveries where order_id = '60000000-0000-0000-0000-000000000001');
    get diagnostics v_count = row_count;
    v_rejected := v_count = 0;
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected, 'append-only attempt delete must be rejected');
end;
$$;

reset role;
set local role anon;
select public.submit_support_request('Consulta visitante', 'Ayuda general', 'Mensaje visitante', 'visitor@test.invalid', null, false, null, null);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select public.submit_support_request('Consulta de cuenta', 'Ayuda de Pedido', 'Mensaje de cuenta', null, null, false, 'order', '60000000-0000-0000-0000-000000000001');
select pg_temp.assert_true((select jsonb_array_length(public.support_requests_view(null)) = 1), 'account must see only its own request');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
select pg_temp.assert_true((select jsonb_array_length(public.support_requests_view(null)) = 0), 'other account must not see foreign support');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true((select jsonb_array_length(public.support_requests_view(null)) = 2), 'support operator must see both non-sensitive requests');
select public.respond_support_request(
  (select (item->>'id')::uuid from jsonb_array_elements(public.support_requests_view(null)) item where item->>'subject' = 'Consulta visitante'),
  'Respuesta operativa', false
);
select public.set_support_request_status(
  (select (item->>'id')::uuid from jsonb_array_elements(public.support_requests_view(null)) item where item->>'subject' = 'Consulta visitante'),
  'closed', 'Resuelta en prueba', null, null
);
select pg_temp.assert_true((select count(*) > 0 from public.audit_events), 'restricted evidence access and sensitive operations must be auditable');

do $$
declare v_rejected boolean := false; v_count integer := 0;
begin
  begin
    update public.support_messages set body = 'mutación prohibida';
    get diagnostics v_count = row_count;
    v_rejected := v_count = 0;
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected, 'append-only support message update must be rejected');
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select pg_temp.assert_true((select count(*) = 0 from public.audit_events), 'operator without audit.read must not see audit events');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true((select count(*) > 0 from public.audit_events), 'operator with audit.read must see audit events');

select 'CM-IMP-04 transactional tests passed' as result;
rollback;
