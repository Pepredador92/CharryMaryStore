import { currentSession } from '../services/auth';
import { loadOrderDetail } from '../services/account';
import { formatMoney } from '../services/catalog';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');
}

const root = document.querySelector<HTMLElement>('[data-order-detail-app]');

if (root) {
  void (async () => {
    try {
      if (!(await currentSession())) {
        window.location.href = `/acceso?next=${encodeURIComponent(window.location.pathname + window.location.search)}`;
        return;
      }
      const orderId = new URLSearchParams(window.location.search).get('id');
      if (!orderId) throw new Error('Falta el identificador del Pedido.');
      const detail = await loadOrderDetail(orderId);
      const order = detail.order as Record<string, string | number>;
      const destination = detail.destination as Record<string, string> | null;
      const content = root!.querySelector<HTMLElement>('[data-order-content]')!;
      content.innerHTML = `<div class="page-heading"><div><span class="badge">${escapeHtml(order.commercial_status)}</span><h1>${escapeHtml(order.order_number)}</h1><p>Creado ${new Intl.DateTimeFormat('es-MX', { dateStyle: 'long', timeStyle: 'short' }).format(new Date(String(order.placed_at)))}</p></div><strong class="price">${formatMoney(Number(order.total_amount_minor), String(order.currency_code))}</strong></div>
        <div class="account-layout"><section class="panel"><h2>Partidas historicas</h2>${detail.items.map((item) => `<article class="order-row"><div><strong>${escapeHtml(item.historical_name)}</strong><br><small>${escapeHtml(item.historical_sku || 'Paquete')} · ${item.quantity} unidad(es)</small>${item.components.length ? `<ul class="component-list">${item.components.map((component) => `<li>${component.total_component_quantity} x ${escapeHtml(component.historical_product_name)} ${escapeHtml(component.historical_presentation_label || '')} · ${escapeHtml(component.historical_sku)}</li>`).join('')}</ul>` : ''}</div><strong>${formatMoney(Number(item.total_amount_minor), String(item.currency_code))}</strong></article>`).join('')}</section>
        <aside class="panel"><h2>Destino confirmado</h2>${destination ? `<p><strong>${escapeHtml(destination.recipient_name)}</strong><br>${escapeHtml(destination.line_1)}${destination.line_2 ? `, ${escapeHtml(destination.line_2)}` : ''}<br>${escapeHtml(destination.neighborhood || '')}<br>${escapeHtml(destination.city)}, ${escapeHtml(destination.region)} ${escapeHtml(destination.postal_code)}<br>${escapeHtml(destination.country_code)}</p>${destination.delivery_instructions ? `<p><strong>Instrucciones</strong><br>${escapeHtml(destination.delivery_instructions)}</p>` : ''}` : '<p>Sin destino visible.</p>'}</aside></div>`;
      root!.querySelector<HTMLElement>('[data-order-loading]')!.hidden = true;
      content.hidden = false;
    } catch (error) {
      root!.querySelector<HTMLElement>('[data-order-loading]')!.hidden = true;
      const target = root!.querySelector<HTMLElement>('[data-order-error]')!;
      target.textContent = error instanceof Error ? error.message : 'No se pudo cargar el Pedido.';
      target.hidden = false;
    }
  })();
}
