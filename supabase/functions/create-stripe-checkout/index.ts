import Stripe from 'npm:stripe@22.0.0';
import { createClient } from 'npm:@supabase/supabase-js@2.110.8';
import { jsonResponse, requireBrowserOrigin } from '../_shared/http.ts';

type CheckoutPayload = {
  order_id: string;
  order_number: string;
  amount_minor: number;
  currency_code: string;
  customer_email: string | null;
  latest_checkout_session_id: string | null;
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    try {
      return new Response(null, { status: 204, headers: requireBrowserOrigin(request) });
    } catch {
      return new Response(null, { status: 403 });
    }
  }

  if (request.method !== 'POST') return jsonResponse(request, { error: 'Method not allowed' }, 405);

  try {
    requireBrowserOrigin(request);
    const stripeSecret = Deno.env.get('STRIPE_SECRET_KEY');
    if (!stripeSecret) throw new Error('Stripe is not configured');

    const { order_id: orderId, payment_token: paymentToken } = await request.json();
    if (typeof orderId !== 'string' || typeof paymentToken !== 'string') {
      return jsonResponse(request, { error: 'Invalid payment request' }, 400);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const stripe = new Stripe(stripeSecret);
    const { data, error } = await supabase.rpc('get_stripe_checkout_payload', {
      p_order_id: orderId,
      p_payment_token: paymentToken,
    });
    if (error) throw error;

    const payload = data as CheckoutPayload;
    if (payload.latest_checkout_session_id) {
      const existing = await stripe.checkout.sessions.retrieve(payload.latest_checkout_session_id);
      if (existing.status === 'open' && existing.url) {
        return jsonResponse(request, {
          checkout_url: existing.url,
          session_id: existing.id,
          order_id: payload.order_id,
          order_number: payload.order_number,
        });
      }
    }

    const origin = request.headers.get('origin')!;
    if (!Number.isInteger(payload.amount_minor) || payload.amount_minor <= 0) {
      throw new Error('Order total is invalid');
    }
    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      client_reference_id: payload.order_id,
      customer_email: payload.customer_email || undefined,
      locale: 'es-419',
      line_items: [{
        quantity: 1,
        price_data: {
          currency: payload.currency_code.trim().toLowerCase(),
          unit_amount: payload.amount_minor,
          product_data: {
            name: `Pedido Cherry Mary ${payload.order_number}`,
          },
        },
      }],
      metadata: { order_id: payload.order_id },
      payment_intent_data: { metadata: { order_id: payload.order_id } },
      success_url: `${origin}/checkout?stripe_session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${origin}/checkout?stripe_cancelled=1`,
    }, {
      idempotencyKey: `cherry-mary:${payload.order_id}:${payload.latest_checkout_session_id ?? 'initial'}`,
    });

    if (!session.url || session.amount_total === null || !session.currency) {
      throw new Error('Stripe did not return a complete Checkout Session');
    }

    const recorded = await supabase.rpc('record_stripe_checkout_session', {
      p_order_id: payload.order_id,
      p_payment_token: paymentToken,
      p_checkout_session_id: session.id,
      p_amount_minor: session.amount_total,
      p_currency_code: session.currency,
      p_expires_at: new Date(session.expires_at * 1000).toISOString(),
    });
    if (recorded.error) throw recorded.error;

    return jsonResponse(request, {
      checkout_url: session.url,
      session_id: session.id,
      order_id: payload.order_id,
      order_number: payload.order_number,
    });
  } catch (error) {
    console.error('create-stripe-checkout', error);
    const message = error instanceof Error && error.message === 'Origin is not allowed'
      ? error.message
      : 'No se pudo iniciar el pago con Stripe.';
    return jsonResponse(request, { error: message }, message === 'Origin is not allowed' ? 403 : 500);
  }
});
