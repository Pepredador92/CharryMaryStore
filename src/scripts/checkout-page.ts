import { loadAccount, type CustomerAddress } from '../services/account';
import { currentSession } from '../services/auth';
import { loadRemoteCart } from '../services/cart';
import { checkoutAuthenticated, checkoutGuest, type DestinationInput } from '../services/checkout';
import { formatMoney, loadPublicCatalog, resolveCartTarget, type CartTarget } from '../services/catalog';
import { clearGuestCart, readGuestCart, type GuestCartItem } from '../stores/guest-cart';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');
}

const root = document.querySelector<HTMLElement>('[data-checkout-app]');

if (root) {
  const form = root.querySelector<HTMLFormElement>('[data-checkout-form]')!;
  let authenticated = false;
  let cartId: string | null = null;
  let items: GuestCartItem[] = [];
  let addresses: CustomerAddress[] = [];
  let resolved: Array<{ item: GuestCartItem; target: CartTarget | null }> = [];

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
      const confirmation = authenticated
        ? await checkoutAuthenticated(cartId!, destination)
        : await checkoutGuest(items, destination);
      if (authenticated) window.dispatchEvent(new CustomEvent('cherry-mary:remote-cart-change'));
      else clearGuestCart();
      form.hidden = true;
      const result = root!.querySelector<HTMLElement>('[data-checkout-confirmation]')!;
      result.innerHTML = `<span class="badge">Pedido creado</span><h1>Gracias por tu compra</h1><p>Tu referencia es <strong>${escapeHtml(confirmation.order_number)}</strong>.</p><p>Total confirmado: <strong>${formatMoney(confirmation.total_amount_minor, confirmation.currency_code)}</strong>.</p><p>Estado comercial: ${escapeHtml(confirmation.commercial_status)}.</p>${authenticated ? `<a class="button primary" href="/cuenta/pedido?id=${confirmation.order_id}">Ver Pedido</a>` : '<p class="notice">La recuperacion en linea de Pedidos de invitado aun no esta disponible. Conserva esta referencia.</p>'}`;
      result.hidden = false;
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (error) {
      const target = root!.querySelector<HTMLElement>('[data-checkout-error]')!;
      target.textContent = error instanceof Error ? error.message : 'No se pudo crear el Pedido.';
      target.hidden = false;
      form.querySelectorAll<HTMLButtonElement>('button').forEach((button) => { button.disabled = false; });
    }
  });

  void initialize();
}
