import { currentSession } from '../services/auth';
import { deactivateAddress, loadAccount, saveAddress, type AccountSnapshot, type CustomerAddress } from '../services/account';
import { formatMoney } from '../services/catalog';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');
}

const root = document.querySelector<HTMLElement>('[data-account-app]');

if (root) {
  let snapshot: AccountSnapshot | null = null;
  const dialog = root.querySelector<HTMLDialogElement>('[data-address-dialog]')!;
  const form = root.querySelector<HTMLFormElement>('[data-address-form]')!;

  async function reload(): Promise<void> {
    const session = await currentSession();
    if (!session) {
      window.location.href = `/acceso?next=${encodeURIComponent('/cuenta')}`;
      return;
    }
    try {
      snapshot = await loadAccount();
      root!.querySelector<HTMLElement>('[data-account-loading]')!.hidden = true;
      root!.querySelector<HTMLElement>('[data-account-content]')!.hidden = false;
      render();
    } catch (error) {
      const target = root!.querySelector<HTMLElement>('[data-account-error]')!;
      target.textContent = error instanceof Error ? error.message : 'No se pudo cargar la cuenta.';
      target.hidden = false;
      root!.querySelector<HTMLElement>('[data-account-loading]')!.hidden = true;
    }
  }

  function render(): void {
    if (!snapshot) return;
    root!.querySelector<HTMLElement>('[data-account-summary]')!.innerHTML = `<p><strong>${escapeHtml(snapshot.context.preferred_name || 'Cliente')}</strong><br>${escapeHtml(snapshot.context.contact_email || 'Sin correo')}<br><span class="badge">${escapeHtml(snapshot.context.account_status)}</span></p>`;
    const addresses = root!.querySelector<HTMLElement>('[data-address-list]')!;
    addresses.innerHTML = snapshot.addresses.length ? snapshot.addresses.map((address) => `<article class="address-row">
      <header><strong>${escapeHtml(address.label || 'Direccion')}</strong><span class="badge">${address.is_active ? 'Activa' : 'Inactiva'}</span></header>
      <p>${escapeHtml(address.recipient_name || '')}<br>${escapeHtml(address.line_1)}${address.line_2 ? `, ${escapeHtml(address.line_2)}` : ''}<br>${escapeHtml(address.neighborhood || '')} ${escapeHtml(address.city)}, ${escapeHtml(address.region)} ${escapeHtml(address.postal_code)}</p>
      <div class="button-row"><button class="button" data-edit-address="${address.id}">Editar</button>${address.is_active ? `<button class="button danger" data-deactivate-address="${address.id}">Desactivar</button>` : ''}</div>
    </article>`).join('') : '<div class="state-box"><div><strong>Sin direcciones</strong>Agrega una para agilizar el checkout.</div></div>';
    const orders = root!.querySelector<HTMLElement>('[data-order-list]')!;
    orders.innerHTML = snapshot.orders.length ? snapshot.orders.map((order) => `<a class="order-row" href="/cuenta/pedido?id=${order.id}"><div><strong>${escapeHtml(order.order_number)}</strong><br><small>${new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium' }).format(new Date(order.placed_at))} · ${escapeHtml(order.commercial_status)}</small></div><strong>${formatMoney(order.total_amount_minor, order.currency_code)}</strong></a>`).join('') : '<div class="state-box"><div><strong>Aun no hay Pedidos</strong>Cuando completes una compra aparecera aqui.</div></div>';
  }

  function fillForm(address?: CustomerAddress): void {
    form.reset();
    const values: Record<string, string> = address ? {
      id: address.id, label: address.label ?? '', recipient_name: address.recipient_name ?? '', contact_phone: address.contact_phone ?? '',
      country_code: address.country_code, line_1: address.line_1, line_2: address.line_2 ?? '', neighborhood: address.neighborhood ?? '',
      city: address.city, region: address.region, postal_code: address.postal_code, delivery_instructions: address.delivery_instructions ?? '',
    } : { country_code: 'MX' };
    Object.entries(values).forEach(([name, value]) => {
      const field = form.elements.namedItem(name) as HTMLInputElement | HTMLTextAreaElement | null;
      if (field) field.value = value;
    });
    dialog.showModal();
  }

  root.addEventListener('click', async (event) => {
    const button = (event.target as Element).closest<HTMLButtonElement>('button');
    if (!button) return;
    if (button.matches('[data-new-address]')) fillForm();
    if (button.matches('[data-close-address]')) dialog.close();
    if (button.dataset.editAddress) fillForm(snapshot?.addresses.find((item) => item.id === button.dataset.editAddress));
    if (button.dataset.deactivateAddress && window.confirm('La direccion dejara de aparecer como activa.')) {
      button.disabled = true;
      try { await deactivateAddress(button.dataset.deactivateAddress); await reload(); } finally { button.disabled = false; }
    }
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!snapshot) return;
    const data = new FormData(form);
    form.querySelectorAll<HTMLButtonElement>('button').forEach((button) => { button.disabled = true; });
    try {
      await saveAddress(snapshot.context, {
        id: String(data.get('id') || '') || undefined,
        label: String(data.get('label') || '') || null,
        recipient_name: String(data.get('recipient_name') || '') || null,
        contact_phone: String(data.get('contact_phone') || '') || null,
        line_1: String(data.get('line_1') || ''),
        line_2: String(data.get('line_2') || '') || null,
        neighborhood: String(data.get('neighborhood') || '') || null,
        city: String(data.get('city') || ''),
        region: String(data.get('region') || ''),
        postal_code: String(data.get('postal_code') || ''),
        country_code: String(data.get('country_code') || 'MX'),
        delivery_instructions: String(data.get('delivery_instructions') || '') || null,
        is_active: true,
      });
      dialog.close();
      await reload();
    } catch (error) {
      window.alert(error instanceof Error ? error.message : 'No se pudo guardar la direccion.');
    } finally {
      form.querySelectorAll<HTMLButtonElement>('button').forEach((button) => { button.disabled = false; });
    }
  });

  void reload();
}
