import { supabase } from '../lib/supabase/client';
import type { GuestCartItem } from '../stores/guest-cart';

export type DestinationInput = {
  recipient_name: string;
  contact_phone: string;
  contact_email: string;
  line_1: string;
  line_2: string;
  neighborhood: string;
  city: string;
  region: string;
  postal_code: string;
  country_code: string;
  delivery_instructions: string;
};

export type OrderConfirmation = {
  order_id: string;
  order_number: string;
  currency_code: string;
  total_amount_minor: number;
  commercial_status: string;
};

export async function checkoutAuthenticated(cartId: string, destination: DestinationInput): Promise<OrderConfirmation> {
  const { data, error } = await supabase.rpc('place_authenticated_order', {
    p_cart_id: cartId,
    p_destination: destination,
  });
  if (error) throw error;
  return data as OrderConfirmation;
}

export async function checkoutGuest(
  items: GuestCartItem[],
  destination: DestinationInput,
): Promise<OrderConfirmation> {
  const { data, error } = await supabase.rpc('place_guest_order', {
    p_items: items.map((item) => ({
      line_kind: item.kind,
      target_id: item.targetId,
      quantity: item.quantity,
    })),
    p_destination: destination,
  });
  if (error) throw error;
  return data as OrderConfirmation;
}
