import Stripe from 'npm:stripe@22.0.0';
import { createClient } from 'npm:@supabase/supabase-js@2.110.8';

const stripeSecret = Deno.env.get('STRIPE_SECRET_KEY');
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SIGNING_SECRET');
const stripe = stripeSecret ? new Stripe(stripeSecret) : null;
const cryptoProvider = Stripe.createSubtleCryptoProvider();

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  if (!stripe || !webhookSecret) return new Response('Stripe is not configured', { status: 503 });

  const signature = request.headers.get('Stripe-Signature');
  if (!signature) return new Response('Stripe signature is required', { status: 400 });

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      await request.text(),
      signature,
      webhookSecret,
      undefined,
      cryptoProvider,
    );
  } catch (error) {
    console.error('stripe-webhook signature', error);
    return new Response('Invalid Stripe signature', { status: 400 });
  }

  const supported = new Set([
    'checkout.session.completed',
    'checkout.session.async_payment_succeeded',
    'checkout.session.async_payment_failed',
    'checkout.session.expired',
  ]);
  if (!supported.has(event.type)) return Response.json({ received: true });

  try {
    const session = event.data.object as Stripe.Checkout.Session;
    const orderId = session.metadata?.order_id;
    if (!orderId) throw new Error('Stripe Session has no Order reference');

    const paymentIntentId = typeof session.payment_intent === 'string'
      ? session.payment_intent
      : session.payment_intent?.id ?? null;
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { error } = await supabase.rpc('apply_stripe_checkout_event', {
      p_event_id: event.id,
      p_event_type: event.type,
      p_order_id: orderId,
      p_checkout_session_id: session.id,
      p_payment_intent_id: paymentIntentId,
      p_payment_status: session.payment_status,
      p_amount_minor: session.amount_total ?? 0,
      p_currency_code: session.currency ?? 'mxn',
      p_occurred_at: new Date(event.created * 1000).toISOString(),
    });
    if (error) throw error;
    return Response.json({ received: true });
  } catch (error) {
    console.error('stripe-webhook processing', error);
    return new Response('Webhook processing failed', { status: 500 });
  }
});
