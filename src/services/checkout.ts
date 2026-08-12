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
  payment_token: string;
};

export type StripeCheckoutStart = {
  checkout_url: string;
  session_id: string;
  order_id: string;
  order_number: string;
};

export type StripeCheckoutStatus = Omit<OrderConfirmation, 'payment_token'> & {
  payment_status: 'pending' | 'processing' | 'paid' | 'failed' | 'expired';
};

export async function checkoutAuthenticated(
  cartId: string,
  destination: DestinationInput,
  paymentToken: string,
): Promise<OrderConfirmation> {
  const { data, error } = await supabase.rpc('place_authenticated_order_for_payment', {
    p_cart_id: cartId,
    p_destination: destination,
    p_payment_token: paymentToken,
  });
  if (error) throw error;
  return data as OrderConfirmation;
}

export async function checkoutGuest(
  items: GuestCartItem[],
  destination: DestinationInput,
  paymentToken: string,
): Promise<OrderConfirmation> {
  const { data, error } = await supabase.rpc('place_guest_order_for_payment', {
    p_items: items.map((item) => ({
      line_kind: item.kind,
      target_id: item.targetId,
      quantity: item.quantity,
    })),
    p_destination: destination,
    p_payment_token: paymentToken,
  });
  if (error) throw error;
  return data as OrderConfirmation;
}

export async function createStripeCheckout(
  confirmation: OrderConfirmation,
): Promise<StripeCheckoutStart> {
  const { data, error } = await supabase.functions.invoke('create-stripe-checkout', {
    body: {
      order_id: confirmation.order_id,
      payment_token: confirmation.payment_token,
    },
  });
  if (error) throw error;
  return data as StripeCheckoutStart;
}

export async function loadStripeCheckoutStatus(sessionId: string): Promise<StripeCheckoutStatus> {
  const { data, error } = await supabase.functions.invoke('stripe-checkout-status', {
    body: { session_id: sessionId },
  });
  if (error) throw error;
  return data as StripeCheckoutStatus;
}
