import { supabase } from '../lib/supabase/client';
import { ensurePersonalContext, type PersonalContext } from './auth';

export type CustomerAddress = {
  id: string;
  customer_id: string;
  label: string | null;
  recipient_name: string | null;
  contact_phone: string | null;
  line_1: string;
  line_2: string | null;
  neighborhood: string | null;
  city: string;
  region: string;
  postal_code: string;
  country_code: string;
  delivery_instructions: string | null;
  is_active: boolean;
};

export type OrderSummary = {
  id: string;
  order_number: string;
  commercial_status: string;
  currency_code: string;
  total_amount_minor: number;
  placed_at: string;
};

export type AccountSnapshot = {
  context: PersonalContext;
  addresses: CustomerAddress[];
  orders: OrderSummary[];
};

export async function loadAccount(): Promise<AccountSnapshot> {
  const context = await ensurePersonalContext();
  const [addresses, orders] = await Promise.all([
    supabase.from('customer_addresses').select('*').order('created_at', { ascending: false }),
    supabase.from('orders').select('*').order('placed_at', { ascending: false }),
  ]);
  if (addresses.error) throw addresses.error;
  if (orders.error) throw orders.error;
  return {
    context,
    addresses: (addresses.data ?? []) as CustomerAddress[],
    orders: (orders.data ?? []) as OrderSummary[],
  };
}

export async function saveAddress(
  context: PersonalContext,
  input: Omit<CustomerAddress, 'id' | 'customer_id'> & { id?: string },
): Promise<void> {
  const payload = {
    label: input.label?.trim() || null,
    recipient_name: input.recipient_name?.trim() || null,
    contact_phone: input.contact_phone?.trim() || null,
    line_1: input.line_1.trim(),
    line_2: input.line_2?.trim() || null,
    neighborhood: input.neighborhood?.trim() || null,
    city: input.city.trim(),
    region: input.region.trim(),
    postal_code: input.postal_code.trim(),
    country_code: input.country_code.trim().toUpperCase(),
    delivery_instructions: input.delivery_instructions?.trim() || null,
    is_active: input.is_active,
  };
  const result = input.id
    ? await supabase
        .from('customer_addresses')
        .update({ ...payload, updated_at: new Date().toISOString() })
        .eq('id', input.id)
    : await supabase.from('customer_addresses').insert({
        id: crypto.randomUUID(),
        customer_id: context.customer_id,
        ...payload,
      });
  if (result.error) throw result.error;
}

export async function deactivateAddress(id: string): Promise<void> {
  const { error } = await supabase
    .from('customer_addresses')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', id);
  if (error) throw error;
}

export async function loadOrderDetail(orderId: string): Promise<{
  order: Record<string, unknown>;
  payment: Record<string, unknown> | null;
  destination: Record<string, unknown> | null;
  items: Array<Record<string, unknown> & { components: Record<string, unknown>[] }>;
}> {
  const [order, payment, destination, items] = await Promise.all([
    supabase.from('orders').select('*').eq('id', orderId).single(),
    supabase.from('order_payments').select('*').eq('order_id', orderId).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('order_destinations').select('*').eq('order_id', orderId).eq('is_current', true).maybeSingle(),
    supabase.from('order_items').select('*').eq('order_id', orderId).order('line_number'),
  ]);
  if (order.error) throw order.error;
  if (payment.error) throw payment.error;
  if (destination.error) throw destination.error;
  if (items.error) throw items.error;
  const itemRows = items.data ?? [];
  const itemIds = itemRows.map((item) => item.id);
  const componentResult = itemIds.length
    ? await supabase.from('order_item_package_components').select('*').in('order_item_id', itemIds)
    : { data: [], error: null };
  if (componentResult.error) throw componentResult.error;
  return {
    order: order.data,
    payment: payment.data,
    destination: destination.data,
    items: itemRows.map((item) => ({
      ...item,
      components: (componentResult.data ?? []).filter((component) => component.order_item_id === item.id),
    })),
  };
}
