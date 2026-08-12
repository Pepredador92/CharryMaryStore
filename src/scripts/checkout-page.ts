import { loadAccount, type CustomerAddress } from '../services/account';
import { currentSession } from '../services/auth';
import { loadRemoteCart } from '../services/cart';
import {
  checkoutAuthenticated,
  checkoutGuest,
  createStripeCheckout,
  loadStripeCheckoutStatus,
  type DestinationInput,
} from '../services/checkout';
import { formatMoney, loadPublicCatalog, resolveCartTarget, type CartTarget } from '../services/catalog';
import { clearGuestCart, readGuestCart, type GuestCartItem } from '../stores/guest-cart';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');
}

const root = document.querySelector<HTMLElement>('[data-checkout-app]');
const paymentTokenKey = 'cherry-mary:stripe-payment-token';
const pendingCheckoutKey = 'cherry-mary:pending-stripe-checkout';

type PendingCheckout = {
  checkout_url: string;
  order_id: string;
  order_number: string;
  authenticated: boolean;
};

if (root) {
  const form = root.querySelector<HTMLFormElement>('[data-checkout-form]')!;
  let authenticated = false;
  let cartId: string | null = null;
  let items: GuestCartItem[] = [];
  let addresses: CustomerAddress[] = [];
  let resolved: Array<{ item: GuestCartItem; target: CartTarget | null }> = [];

  function confirmationTarget(): HTMLElement {
    root!.querySelector<HTMLElement>('[data-checkout-loading]')!.hidden = true;
    form.hidden = true;
    const target = root!.querySelector<HTMLElement>('[data-checkout-confirmation]')!;
    target.hidden = false;
    return target;
  }

  async function showStripeReturn(sessionId: string): Promise<void> {
    try {
      const [session, status] = await Promise.all([
        currentSession(),
        loadStripeCheckoutStatus(sessionId),
      ]);
      authenticated = Boolean(session);
      if (status.payment_status === 'paid') {
        if (authenticated) window.dispatchEvent(new CustomEvent('cherry-mary:remote-cart-change'));
        else clearGuestCart();
        sessionStorage.removeItem(paymentTokenKey);
        sessionStorage.removeItem(pendingCheckoutKey);
      }

      const paid = status.payment_status === 'paid';
      const target = confirmationTarget();
      target.innerHTML = `<span class="badge">${paid ? 'Pago confirmado' : 'Pago en proceso'}</span><h1>${paid ? 'Gracias por tu compra' : 'Estamos confirmando tu pago'}</h1><p>Tu referencia es <strong>${escapeHtml(status.order_number)}</strong>.</p><p>Total: <strong>${formatMoney(status.total_amount_minor, status.currency_code)}</strong>.</p>${paid ? '<p>Stripe confirmo el pago correctamente.</p>' : '<p>Actualiza esta pagina en unos momentos. El Pedido no avanzara hasta recibir la confirmacion de Stripe.</p>'}${authenticated ? `<a class="button primary" href="/cuenta/pedido?id=${status.order_id}">Ver Pedido</a>` : '<p class="notice">Conserva la referencia para cualquier consulta.</p>'}`;
    } catch (error) {
      const target = root!.querySelector<HTMLElement>('[data-checkout-error]')!;
      root!.querySelector<HTMLElement>('[data-checkout-loading]')!.hidden = true;
      target.textContent = error instanceof Error ? error.message : 'No se pudo confirmar el pago.';
      target.hidden = false;
    }
  }

  function showStripeCancellation(): void {
    root!.querySelector<HTMLElement>('[data-checkout-loading]')!.hidden = true;
    const saved = sessionStorage.getItem(pendingCheckoutKey);
    let pending: PendingCheckout | null = null;
    try { pending = saved ? JSON.parse(saved) as PendingCheckout : null; } catch { pending = null; }
    const checkoutUrl = pending?.checkout_url?.startsWith('https://checkout.stripe.com/')
      ? pending.checkout_url
      : null;
    const target = confirmationTarget();
    target.innerHTML = `<span class="badge">Pago pendiente</span><h1>No se realizo ningun cargo</h1><p>Puedes volver a Stripe para completar el pago cuando estes listo.</p>${checkoutUrl ? `<a class="button primary" href="${escapeHtml(checkoutUrl)}">Reanudar pago</a>` : '<a class="button" href="/carrito">Volver al carrito</a>'}`;
  }

  function setField(name: string, value: string | null): void {
    const field = form.elements.namedItem(name) as HTMLInputElement | HTMLTextAreaElement | null;
    if (field) field.value = value ?? '';
  }

  function applyAddress(address: CustomerAddress | undefined): void {
    if (!address) return;
    setField('recipient_name', address.recipient_name);
    setField('contact_phone', address.contact_phone);
    setField('line_1', address.line_1);
    setField('line_2', address.line_2);
    setField('neighborhood', address.neighborhood);
    setField('city', address.city);
    setField('region', address.region);
    setField('postal_code', address.postal_code);
    setField('country_code', address.country_code);
    setField('delivery_instructions', address.delivery_instructions);
  }

  async function initialize(): Promise<void> {
    try {
      const [session, catalog] = await Promise.all([currentSession(), loadPublicCatalog()]);
      authenticated = Boolean(session);
      if (session) {
        const [cart, account] = await Promise.all([loadRemoteCart(), loadAccount()]);
        cartId = cart.id;
        items = cart.lines.map((line) => ({
          kind: line.line_kind,
          targetId: line.presentation_id ?? line.package_id ?? '',
          quantity: line.quantity,
        }));
        addresses = account.addresses.filter((address) => address.is_active);
        setField('recipient_name', account.context.preferred_name);
        setField('contact_email', account.context.contact_email);
        setField('contact_phone', account.context.contact_phone);
        const picker = root!.querySelector<HTMLSelectElement>('[data-address-picker]')!;
        const label = root!.querySelector<HTMLElement>('[data-address-picker-label]')!;
        if (addresses.length) {
          picker.insertAdjacentHTML('beforeend', addresses.map((address) => `<option value="${address.id}">${escapeHtml(address.label || address.line_1)}</option>`).join(''));
          label.hidden = false;
        }
      } else {
        items = readGuestCart().items;
      }

      resolved = items.map((item) => ({ item, target: resolveCartTarget(catalog, item.kind, item.targetId) }));
      if (!items.length) throw new Error('El carrito esta vacio.');
      if (resolved.some(({ item, target }) => !target || !target.sellable || target.availability < item.quantity)) {
        throw new Error('Uno o mas articulos ya no tienen disponibilidad suficiente. Regresa al carrito para corregirlos.');
      }
      const currencies = new Set(resolved.map(({ target }) => target!.currencyCode));
      if (currencies.size !== 1) throw new Error('Los articulos del carrito no comparten la misma moneda.');
      const total = resolved.reduce((sum, row) => sum + row.target!.priceAmountMinor * row.item.quantity, 0);
      root!.querySelector<HTMLElement>('[data-checkout-total]')!.textContent = formatMoney(total, resolved[0].target!.currencyCode);
      root!.querySelector<HTMLElement>('[data-checkout-lines]')!.innerHTML = resolved.map(({ item, target }) => `<div class="summary-row"><span>${item.quantity} x ${escapeHtml(target!.name)}<small><br>${escapeHtml(target!.detail)}</small></span><strong>${formatMoney(target!.priceAmountMinor * item.quantity, target!.currencyCode)}</strong></div>`).join('');
      root!.querySelector<HTMLElement>('[data-checkout-loading]')!.hidden = true;
      form.hidden = false;
    } catch (error) {
      root!.querySelector<HTMLElement>('[data-checkout-loading]')!.hidden = true;
      const target = root!.querySelector<HTMLElement>('[data-checkout-error]')!;
      target.textContent = error instanceof Error ? error.message : 'No se pudo preparar el checkout.';
      target.hidden = false;
    }
  }

  root.querySelector<HTMLSelectElement>('[data-address-picker]')?.addEventListener('change', (event) => {
    const id = (event.target as HTMLSelectElement).value;
    applyAddress(addresses.find((address) => address.id === id));
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const data = new FormData(form);
    const destination: DestinationInput = {
      recipient_name: String(data.get('recipient_name') ?? '').trim(),
      contact_phone: String(data.get('contact_phone') ?? '').trim(),
      contact_email: String(data.get('contact_email') ?? '').trim(),
      line_1: String(data.get('line_1') ?? '').trim(),
      line_2: String(data.get('line_2') ?? '').trim(),
      neighborhood: String(data.get('neighborhood') ?? '').trim(),
      city: String(data.get('city') ?? '').trim(),
      region: String(data.get('region') ?? '').trim(),
      postal_code: String(data.get('postal_code') ?? '').trim(),
      country_code: String(data.get('country_code') ?? '').trim().toUpperCase(),
      delivery_instructions: String(data.get('delivery_instructions') ?? '').trim(),
    };
    if (!destination.contact_email && !destination.contact_phone) {
      const target = root!.querySelector<HTMLElement>('[data-checkout-error]')!;
      target.textContent = 'Indica al menos correo o telefono de contacto.';
      target.hidden = false;
      return;
    }
    form.querySelectorAll<HTMLButtonElement>('button').forEach((button) => { button.disabled = true; });
    try {
      const paymentToken = sessionStorage.getItem(paymentTokenKey) ?? crypto.randomUUID();
      sessionStorage.setItem(paymentTokenKey, paymentToken);
      const confirmation = authenticated
        ? await checkoutAuthenticated(cartId!, destination, paymentToken)
        : await checkoutGuest(items, destination, paymentToken);
      const checkout = await createStripeCheckout(confirmation);
      sessionStorage.setItem(pendingCheckoutKey, JSON.stringify({
        checkout_url: checkout.checkout_url,
        order_id: checkout.order_id,
        order_number: checkout.order_number,
        authenticated,
      } satisfies PendingCheckout));
      window.location.assign(checkout.checkout_url);
    } catch (error) {
      const target = root!.querySelector<HTMLElement>('[data-checkout-error]')!;
      target.textContent = error instanceof Error ? error.message : 'No se pudo crear el Pedido.';
      target.hidden = false;
      form.querySelectorAll<HTMLButtonElement>('button').forEach((button) => { button.disabled = false; });
    }
  });

  const query = new URLSearchParams(window.location.search);
  const stripeSessionId = query.get('stripe_session_id');
  if (stripeSessionId) void showStripeReturn(stripeSessionId);
  else if (query.get('stripe_cancelled') === '1') showStripeCancellation();
  else void initialize();
}
