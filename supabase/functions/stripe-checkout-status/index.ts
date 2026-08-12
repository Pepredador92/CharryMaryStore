import Stripe from 'npm:stripe@22.0.0';
import { createClient } from 'npm:@supabase/supabase-js@2.110.8';
import { jsonResponse, requireBrowserOrigin } from '../_shared/http.ts';

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
    const { session_id: sessionId } = await request.json();
    if (typeof sessionId !== 'string' || !sessionId.startsWith('cs_')) {
      return jsonResponse(request, { error: 'Invalid Checkout Session' }, 400);
    }

    const stripe = new Stripe(stripeSecret);
    const session = await stripe.checkout.sessions.retrieve(sessionId);
    const orderId = session.metadata?.order_id;
    if (!orderId) throw new Error('Stripe Session has no Order reference');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    if (session.status === 'complete') {
      const paymentIntentId = typeof session.payment_intent === 'string'
        ? session.payment_intent
        : session.payment_intent?.id ?? null;
      const applied = await supabase.rpc('apply_stripe_checkout_event', {
        p_event_id: `checkout-status:${session.id}:${session.payment_status}`,
        p_event_type: 'checkout.session.completed',
        p_order_id: orderId,
        p_checkout_session_id: session.id,
        p_payment_intent_id: paymentIntentId,
        p_payment_status: session.payment_status,
        p_amount_minor: session.amount_total ?? 0,
        p_currency_code: session.currency ?? 'mxn',
        p_occurred_at: new Date().toISOString(),
      });
      if (applied.error) throw applied.error;
    }

    const status = await supabase.rpc('get_stripe_checkout_status', {
      p_checkout_session_id: session.id,
    });
    if (status.error) throw status.error;

    return jsonResponse(request, {
      order_id: status.data.order_id,
      order_number: status.data.order_number,
      commercial_status: status.data.commercial_status,
      total_amount_minor: status.data.total_amount_minor,
      currency_code: status.data.currency_code,
      payment_status: status.data.payment_status,
    });
  } catch (error) {
    console.error('stripe-checkout-status', error);
    return jsonResponse(request, { error: 'No se pudo confirmar el estado del pago.' }, 500);
  }
});
