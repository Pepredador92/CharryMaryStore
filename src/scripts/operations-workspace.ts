import { supabase } from '../lib/supabase/client';
import { getCurrentCapabilities } from '../lib/admin/catalog';
import {
  archiveOrderWorkflow,
  assignDelivery,
  authorizePreparation,
  createDelivery,
  deleteSupportRequest,
  deleteDeliveryEvidence,
  loadAuditEvents,
  loadDeliveries,
  loadDeliveryAssignmentOptions,
  loadDeliveryDetail,
  loadDeliveryEvidence,
  loadOperationalDashboard,
  loadOrderDetail,
  loadOrders,
  loadPreparationDetail,
  loadPreparations,
  loadSupportRequests,
  loadSupportReferenceOptions,
  manageOrder,
  managePreparation,
  recordDeliveryCustody,
  registerDeliveryAttempt,
  registerDeliveryEvidence,
  respondSupport,
  saveLogisticsProvider,
  setDeliveryState,
  setSupportStatus,
  type JsonRecord,
} from '../lib/admin/operations';

type Section = 'dashboard' | 'orders' | 'order' | 'preparation' | 'preparation-detail' | 'deliveries' | 'delivery-detail' | 'support' | 'support-detail' | 'audit';
type SubmitHandler = (data: FormData) => Promise<void>;

const dateFormatter = new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium', timeStyle: 'short' });

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function formatDate(value: unknown): string {
  return value ? dateFormatter.format(new Date(String(value))) : '—';
}

function money(value: unknown, currency = 'MXN'): string {
  return new Intl.NumberFormat('es-MX', { style: 'currency', currency }).format(Number(value ?? 0) / 100);
}

function badge(status: unknown): string {
  const value = String(status ?? 'sin estado');
  const tone = ['confirmed', 'completed', 'resolved', 'delivered', 'verified'].includes(value)
    ? 'active'
    : ['cancelled', 'blocked', 'ended_incomplete', 'closed', 'failed', 'invalidated'].includes(value)
      ? 'archived'
      : 'inactive';
  return `<span class="badge ${tone}">${escapeHtml(value.replaceAll('_', ' '))}</span>`;
}

function empty(title: string): string {
  return `<div class="state-box"><div><strong>${escapeHtml(title)}</strong></div></div>`;
}

function table(headers: string[], rows: string): string {
  return `<div class="table-wrap"><table class="data-table"><thead><tr>${headers.map((item) => `<th>${escapeHtml(item)}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table></div>`;
}

class OperationsWorkspace {
  private root: HTMLElement;
  private section: Section;
  private capabilities = new Set<string>();
  private data: any = null;
  private submitHandler: SubmitHandler | null = null;

  constructor(root: HTMLElement) {
    this.root = root;
    this.section = root.dataset.section as Section;
    this.bind();
    void this.initialize();
  }

  private el<T extends Element>(selector: string): T {
    const element = this.root.querySelector<T>(selector);
    if (!element) throw new Error(`Falta ${selector}`);
    return element;
  }

  private optional<T extends Element>(selector: string): T | null {
    return this.root.querySelector<T>(selector);
  }

  private bind(): void {
    this.optional<HTMLFormElement>('[data-auth-form]')?.addEventListener('submit', (event) => void this.signIn(event));
    document.querySelector<HTMLButtonElement>('[data-sign-out]')?.addEventListener('click', () => void this.signOut());
    this.root.addEventListener('click', (event) => void this.click(event));
    this.root.addEventListener('submit', (event) => {
      const form = event.target as HTMLFormElement;
      if (form.matches('[data-admin-support-reply]')) void this.submitSupportReply(event);
    });
    this.optional<HTMLInputElement>('[data-search]')?.addEventListener('input', () => this.render());
    this.optional<HTMLSelectElement>('[data-status-filter]')?.addEventListener('change', () => this.render());
    this.optional<HTMLInputElement>('[data-date-from]')?.addEventListener('change', () => this.render());
    this.optional<HTMLInputElement>('[data-date-to]')?.addEventListener('change', () => this.render());
    this.el<HTMLFormElement>('[data-operation-form]').addEventListener('submit', (event) => void this.submitDialog(event));
  }

  private async initialize(): Promise<void> {
    const { data, error } = await supabase.auth.getSession();
    if (error || !data.session) {
      this.showAuth(error?.message);
      return;
    }
    await this.activate(data.session.user.email ?? 'Cuenta operativa');
  }

  private async signIn(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    this.busy(form, true);
    const result = await supabase.auth.signInWithPassword({
      email: String(data.get('email') ?? '').trim(),
      password: String(data.get('password') ?? ''),
    });
    this.busy(form, false);
    if (result.error || !result.data.session) {
      this.showAuth(result.error?.message ?? 'No fue posible iniciar sesión.');
      return;
    }
    await this.activate(result.data.user.email ?? 'Cuenta operativa');
  }

  private async signOut(): Promise<void> {
    await supabase.auth.signOut();
    this.capabilities.clear();
    this.showAuth();
  }

  private showAuth(message?: string): void {
    this.el<HTMLElement>('[data-loading-state]').hidden = true;
    this.el<HTMLElement>('[data-access-state]').hidden = true;
    this.el<HTMLElement>('[data-workspace-content]').hidden = true;
    this.el<HTMLElement>('[data-auth-panel]').hidden = false;
    const error = this.el<HTMLElement>('[data-auth-error]');
    error.hidden = !message;
    error.textContent = message ?? '';
    const signOut = document.querySelector<HTMLButtonElement>('[data-sign-out]');
    const email = document.querySelector<HTMLElement>('[data-session-email]');
    if (signOut) signOut.hidden = true;
    if (email) email.textContent = 'Sesión no iniciada';
  }

  private async activate(emailAddress: string): Promise<void> {
    this.el<HTMLElement>('[data-auth-panel]').hidden = true;
    this.el<HTMLElement>('[data-loading-state]').hidden = false;
    const email = document.querySelector<HTMLElement>('[data-session-email]');
    const signOut = document.querySelector<HTMLButtonElement>('[data-sign-out]');
    if (email) email.textContent = emailAddress;
    if (signOut) signOut.hidden = false;
    try {
      this.capabilities = await getCurrentCapabilities();
      if (!this.canAccess()) {
        this.el<HTMLElement>('[data-loading-state]').hidden = true;
        this.el<HTMLElement>('[data-access-state]').hidden = false;
        return;
      }
      await this.reload();
      this.el<HTMLElement>('[data-loading-state]').hidden = true;
      this.el<HTMLElement>('[data-access-state]').hidden = true;
      this.el<HTMLElement>('[data-workspace-content]').hidden = false;
    } catch (error) {
      this.el<HTMLElement>('[data-loading-state]').hidden = true;
      this.toast(this.message(error), 'error');
    }
  }

  private can(code: string): boolean {
    return this.capabilities.has(code);
  }

  private any(...codes: string[]): boolean {
    return codes.some((code) => this.can(code));
  }

  private canAccess(): boolean {
    if (this.section === 'dashboard') return this.capabilities.size > 0;
    if (this.section === 'orders' || this.section === 'order') return this.any('orders.read', 'orders.manage');
    if (this.section.startsWith('preparation')) return this.any('preparation.read', 'preparation.operate', 'preparation.manage');
    if (this.section.startsWith('deliver')) return this.any('delivery.read', 'delivery.operate', 'delivery.manage');
    if (this.section.startsWith('support')) return this.any('support.handle', 'support.sensitive');
    return this.can('audit.read');
  }

  private queryId(): string {
    const id = new URLSearchParams(location.search).get('id');
    if (!id) throw new Error('Falta el identificador solicitado.');
    return id;
  }

  private async reload(): Promise<void> {
    if (this.section === 'dashboard') this.data = await loadOperationalDashboard();
    if (this.section === 'orders') this.data = await loadOrders();
    if (this.section === 'order') this.data = await loadOrderDetail(this.queryId());
    if (this.section === 'preparation') this.data = await loadPreparations();
    if (this.section === 'preparation-detail') this.data = await loadPreparationDetail(this.queryId());
    if (this.section === 'deliveries') this.data = await loadDeliveries();
    if (this.section === 'delivery-detail') this.data = await loadDeliveryDetail(this.queryId());
    if (this.section === 'support') this.data = await loadSupportRequests();
    if (this.section === 'support-detail') this.data = await loadSupportRequests(this.queryId());
    if (this.section === 'audit') this.data = await loadAuditEvents();
    this.configureFilters();
    this.render();
  }

  private configureFilters(): void {
    const select = this.optional<HTMLSelectElement>('[data-status-filter]');
    if (!select) return;
    const values: Record<string, string[]> = {
      orders: ['pending_confirmation', 'confirmed', 'cancelled'],
      preparation: ['pending', 'in_progress', 'blocked', 'completed', 'ended_incomplete', 'reopened'],
      deliveries: ['pending', 'in_custody', 'in_transit', 'blocked', 'completed', 'reopened'],
      support: ['open', 'in_attention', 'resolved', 'channelled', 'closed'],
      audit: ['catalog', 'access', 'customer', 'order', 'inventory', 'preparation', 'delivery', 'support'],
    };
    const label = this.section === 'audit' ? 'Todas las áreas' : 'Todos los estados';
    const defaultValue = this.section === 'orders' ? '__active__' : '';
    const defaultLabel = this.section === 'orders' ? 'Pedidos activos' : label;
    select.innerHTML = `<option value="${defaultValue}">${defaultLabel}</option>${(values[this.section] ?? []).map((value) => `<option value="${value}">${value.replaceAll('_', ' ')}</option>`).join('')}${this.section === 'orders' ? `<option value="">${label}</option>` : ''}`;
  }

  private render(): void {
    if (this.section === 'dashboard') this.renderDashboard();
    if (this.section === 'orders') this.renderOrders();
    if (this.section === 'order') this.renderOrder();
    if (this.section === 'preparation') this.renderPreparations();
    if (this.section === 'preparation-detail') this.renderPreparation();
    if (this.section === 'deliveries') this.renderDeliveries();
    if (this.section === 'delivery-detail') this.renderDelivery();
    if (this.section === 'support') this.renderSupport();
    if (this.section === 'support-detail') this.renderSupportDetail();
    if (this.section === 'audit') this.renderAudit();
  }

  private renderDashboard(): void {
    const cards = [
      ['Pedidos pendientes', this.data.orders_pending, '/admin/pedidos'],
      ['Pedidos confirmados', this.data.orders_confirmed, '/admin/pedidos'],
      ['Preparaciones pendientes', this.data.preparations_pending, '/admin/preparacion'],
      ['Preparaciones en curso', this.data.preparations_in_progress, '/admin/preparacion'],
      ['Preparaciones bloqueadas', this.data.preparations_blocked, '/admin/preparacion'],
      ['Entregas pendientes', this.data.deliveries_pending, '/admin/entregas'],
      ['Entregas activas', this.data.deliveries_active, '/admin/entregas'],
      ['Atención abierta', this.data.support_open, '/admin/atencion'],
      ['Inventario bajo', this.data.low_inventory, '/admin/inventario'],
    ].filter(([, value]) => value !== null && value !== undefined);
    this.content().innerHTML = `<div class="panel-body"><div class="stats-grid operation-stats">${cards.map(([label, value, href], index) => `<a class="stat ${index === 0 ? 'accent' : ''}" href="${href}"><span>${label}</span><strong>${value}</strong></a>`).join('')}</div></div>`;
  }

  private filtered(rows: JsonRecord[], statusKey = 'status'): JsonRecord[] {
    const term = this.optional<HTMLInputElement>('[data-search]')?.value.trim().toLowerCase() ?? '';
    const status = this.optional<HTMLSelectElement>('[data-status-filter]')?.value ?? '';
    return rows.filter((row) => {
      const rowStatus = String(row[statusKey]);
      const matchesStatus = status === '__active__' ? rowStatus !== 'cancelled' : !status || rowStatus === status;
      return matchesStatus && (!term || JSON.stringify(row).toLowerCase().includes(term));
    });
  }

  private renderOrders(): void {
    const rows = this.filtered(this.data as JsonRecord[], 'commercial_status');
    this.content().innerHTML = rows.length ? table(['Pedido', 'Estado', 'Total', 'Fecha', ''], rows.map((order) => `<tr><td><span class="cell-title mono">${escapeHtml(order.order_number)}</span></td><td>${badge(order.commercial_status)}</td><td>${money(order.total_amount_minor, order.currency_code)}</td><td>${formatDate(order.placed_at)}</td><td><a class="button small" href="/admin/pedidos/detalle?id=${order.id}">Abrir</a></td></tr>`).join('')) : empty('No hay pedidos');
  }

  private renderOrder(): void {
    const { order, customer, destination, items, actions } = this.data;
    const itemRows = (items as JsonRecord[]).map((item) => `<tr><td>${item.line_number}</td><td><span class="cell-title">${escapeHtml(item.historical_name)}</span><span class="cell-subtitle mono">${escapeHtml(item.historical_sku ?? item.item_kind)}</span>${item.components?.length ? `<div class="snapshot-components">${item.components.map((component: JsonRecord) => `${escapeHtml(component.historical_product_name)} · ${escapeHtml(component.historical_sku)} × ${component.total_component_quantity}`).join('<br>')}</div>` : ''}</td><td>${item.quantity}</td><td>${money(item.total_amount_minor, item.currency_code)}</td></tr>`).join('');
    const actionRows = (actions as JsonRecord[]).map((action) => `<tr><td>${formatDate(action.occurred_at)}</td><td>${badge(action.action_kind)}</td><td>${escapeHtml(action.cause ?? '—')}</td></tr>`).join('');
    this.content().innerHTML = `<div class="panel-body detail-stack">
      <div class="detail-grid"><div><span>Pedido</span><strong class="mono">${escapeHtml(order.order_number)}</strong></div><div><span>Estado</span>${badge(order.commercial_status)}</div><div><span>Cliente</span><strong>${escapeHtml(customer.preferred_name || 'Sin nombre')}</strong><small>${escapeHtml(customer.contact_email || customer.contact_phone || 'Sin contacto')}</small></div><div><span>Total</span><strong>${money(order.total_amount_minor, order.currency_code)}</strong></div></div>
      <section><h2>Destino</h2><p>${escapeHtml(destination?.recipient_name)} · ${escapeHtml(destination?.line_1)} ${escapeHtml(destination?.line_2 ?? '')}<br>${escapeHtml(destination?.city)}, ${escapeHtml(destination?.region)} ${escapeHtml(destination?.postal_code)}</p></section>
      <section><h2>Partidas</h2>${table(['#', 'Partida histórica', 'Cantidad', 'Total'], itemRows)}</section>
      <section><h2>Acciones</h2>${actionRows ? table(['Fecha', 'Acción', 'Causa'], actionRows) : empty('Sin acciones operativas')}</section>
    </div>`;
    const actionsRoot = this.actions();
    actionsRoot.innerHTML = `<a class="button" href="/admin/pedidos">Volver</a>${this.can('orders.manage') && order.commercial_status === 'pending_confirmation' ? `<button class="button primary" data-action="confirm-order" data-id="${order.id}">Confirmar</button>` : ''}${this.can('orders.manage') && ['pending_confirmation', 'confirmed'].includes(order.commercial_status) && !order.preparation_authorized_at ? `<button class="button danger" data-action="cancel-order" data-id="${order.id}">Cancelar</button>` : ''}${this.can('orders.manage') && order.commercial_status === 'confirmed' && !order.preparation_authorized_at ? `<button class="button primary" data-action="authorize-preparation" data-id="${order.id}">Autorizar preparación</button>` : ''}${this.can('orders.manage') ? `<button class="button danger" data-action="archive-order" data-id="${order.id}">Retirar del panel</button>` : ''}`;
  }

  private renderPreparations(): void {
    const rows = this.filtered(this.data as JsonRecord[]);
    this.content().innerHTML = rows.length ? table(['Pedido', 'Estado', 'Responsable', 'Inicio', ''], rows.map((item) => `<tr><td><span class="cell-title mono">${escapeHtml(item.orders?.order_number)}</span></td><td>${badge(item.status)}</td><td class="mono">${escapeHtml(item.current_responsible_person_id ?? 'Sin asignar')}</td><td>${formatDate(item.started_at)}</td><td><a class="button small" href="/admin/preparacion/detalle?id=${item.id}">Abrir</a></td></tr>`).join('')) : empty('No hay preparaciones');
  }

  private renderPreparation(): void {
    const { preparation, order, items, actions } = this.data;
    const itemRows = (items as JsonRecord[]).map((item) => `<tr><td>${item.line_number}</td><td><span class="cell-title">${escapeHtml(item.historical_name)}</span>${item.components?.length ? `<span class="cell-subtitle">${item.components.map((component: JsonRecord) => `${escapeHtml(component.historical_sku)} × ${component.total_component_quantity}`).join(' · ')}</span>` : ''}</td><td>${badge(item.verification?.verification_status)}</td><td>${this.any('preparation.operate', 'preparation.manage') && ['in_progress', 'reopened'].includes(preparation.status) ? `<button class="button small" data-action="verify-item" data-id="${item.id}">Verificar</button>${item.verification?.verification_status === 'verified' ? `<button class="button small danger" data-action="invalidate-item" data-id="${item.id}">Invalidar</button>` : ''}` : ''}</td></tr>`).join('');
    const history = (actions as JsonRecord[]).map((action) => `<tr><td>${formatDate(action.occurred_at)}</td><td>${escapeHtml(action.action_kind)}</td><td>${escapeHtml(action.result ?? '—')}</td><td>${escapeHtml(action.cause ?? '—')}</td></tr>`).join('');
    this.content().innerHTML = `<div class="panel-body detail-stack"><div class="detail-grid"><div><span>Pedido</span><strong class="mono">${escapeHtml(order.order_number)}</strong></div><div><span>Estado</span>${badge(preparation.status)}</div><div><span>Inicio</span><strong>${formatDate(preparation.started_at)}</strong></div><div><span>Responsable</span><strong class="mono">${escapeHtml(preparation.current_responsible_person_id ?? 'Sin asignar')}</strong></div></div><section><h2>Verificación</h2>${table(['#', 'Partida', 'Estado', ''], itemRows)}</section><section><h2>Historial</h2>${history ? table(['Fecha', 'Acción', 'Resultado', 'Causa'], history) : empty('Sin acciones')}</section></div>`;
    const canOperate = this.any('preparation.operate', 'preparation.manage');
    this.actions().innerHTML = `<a class="button" href="/admin/preparacion">Volver</a>${canOperate && ['pending', 'reopened'].includes(preparation.status) ? `<button class="button primary" data-action="prep-action" data-kind="start">Comenzar</button>` : ''}${canOperate && ['pending', 'in_progress', 'reopened'].includes(preparation.status) ? `<button class="button danger" data-action="prep-cause" data-kind="block">Bloquear</button>` : ''}${canOperate && preparation.status === 'blocked' ? `<button class="button" data-action="prep-action" data-kind="unblock">Desbloquear</button>` : ''}${canOperate && ['in_progress', 'reopened'].includes(preparation.status) ? `<button class="button primary" data-action="prep-action" data-kind="complete">Completar</button>` : ''}${canOperate && ['pending', 'in_progress', 'blocked', 'reopened'].includes(preparation.status) ? `<button class="button danger" data-action="prep-cause" data-kind="end_incomplete">Terminar incompleta</button>` : ''}${this.can('preparation.manage') && ['completed', 'ended_incomplete'].includes(preparation.status) ? `<button class="button" data-action="prep-cause" data-kind="reopen">Reabrir</button>` : ''}${this.can('delivery.manage') && preparation.status === 'completed' ? `<button class="button primary" data-action="create-delivery" data-id="${order.id}">Crear entrega</button>` : ''}${this.can('orders.manage') ? `<button class="button danger" data-action="archive-order" data-id="${order.id}">Retirar del panel</button>` : ''}`;
  }

  private renderDeliveries(): void {
    const rows = this.filtered(this.data as JsonRecord[]);
    this.content().innerHTML = rows.length ? table(['Pedido', 'Estado', 'Resultado', 'Reconocida', ''], rows.map((item) => `<tr><td><span class="cell-title mono">${escapeHtml(item.orders?.order_number)}</span></td><td>${badge(item.status)}</td><td>${escapeHtml(item.final_result ?? '—')}</td><td>${formatDate(item.recognized_at)}</td><td><a class="button small" href="/admin/entregas/detalle?id=${item.id}">Abrir</a></td></tr>`).join('')) : empty('No hay entregas');
    this.actions().innerHTML = this.can('delivery.manage') ? '<button class="button" data-action="new-provider">Nuevo proveedor</button>' : '';
  }

  private renderDelivery(): void {
    const { delivery, order, destination, assignments, custody_events: custody, attempts, actions } = this.data;
    const assignmentRows = (assignments as JsonRecord[]).map((item) => `<tr><td>${escapeHtml(item.person_name ?? item.provider_name ?? '—')}</td><td>${escapeHtml(item.assignment_kind)}</td><td>${formatDate(item.started_at)}</td><td>${formatDate(item.ended_at)}</td></tr>`).join('');
    const attemptRows = (attempts as JsonRecord[]).map((item) => `<tr><td>${item.attempt_number}</td><td>${badge(item.result)}</td><td>${formatDate(item.completed_at)}</td><td>${escapeHtml(item.failure_cause ?? item.receipt_confirmation ?? '—')}</td></tr>`).join('');
    const custodyRows = (custody as JsonRecord[]).map((item) => `<tr><td>${formatDate(item.occurred_at)}</td><td>${escapeHtml(item.event_kind)}</td><td>${escapeHtml(item.from_party_kind)} → ${escapeHtml(item.to_party_kind)}</td><td>${escapeHtml(item.cause ?? '—')}</td></tr>`).join('');
    const actionRows = (actions as JsonRecord[]).map((item) => `<tr><td>${formatDate(item.occurred_at)}</td><td>${escapeHtml(item.action_kind)}</td><td>${escapeHtml(item.cause)}</td></tr>`).join('');
    this.content().innerHTML = `<div class="panel-body detail-stack"><div class="detail-grid"><div><span>Pedido</span><strong class="mono">${escapeHtml(order.order_number)}</strong></div><div><span>Estado</span>${badge(delivery.status)}</div><div><span>Resultado</span><strong>${escapeHtml(delivery.final_result ?? 'Pendiente')}</strong></div><div><span>Destino</span><strong>${escapeHtml(destination?.city)}, ${escapeHtml(destination?.region)}</strong></div></div><section><h2>Asignaciones</h2>${assignmentRows ? table(['Responsable', 'Tipo', 'Inicio', 'Fin'], assignmentRows) : empty('Sin asignación')}</section><section><h2>Custodia</h2>${custodyRows ? table(['Fecha', 'Evento', 'Transferencia', 'Causa'], custodyRows) : empty('Sin eventos de custodia')}</section><section><h2>Intentos</h2>${attemptRows ? table(['#', 'Resultado', 'Fecha', 'Detalle'], attemptRows) : empty('Sin intentos')}</section><section><h2>Evidencia</h2><div data-evidence>${this.any('delivery_evidence.read', 'delivery_evidence.manage') ? empty('Cargando evidencia') : empty('Acceso restringido')}</div></section><section><h2>Acciones</h2>${actionRows ? table(['Fecha', 'Acción', 'Causa'], actionRows) : empty('Sin acciones')}</section></div>`;
    const active = ['pending', 'in_custody', 'in_transit', 'blocked', 'reopened'].includes(delivery.status);
    this.actions().innerHTML = `<a class="button" href="/admin/entregas">Volver</a>${this.can('delivery.manage') && active ? '<button class="button" data-action="assign-delivery">Asignar</button>' : ''}${this.any('delivery.operate', 'delivery.manage') && active ? '<button class="button" data-action="custody-delivery">Custodia</button>' : ''}${this.any('delivery.operate', 'delivery.manage') && ['in_custody', 'reopened'].includes(delivery.status) ? '<button class="button primary" data-action="delivery-cause" data-kind="start_transit">Iniciar tránsito</button>' : ''}${this.any('delivery.operate', 'delivery.manage') && ['in_custody', 'in_transit', 'reopened'].includes(delivery.status) ? '<button class="button primary" data-action="delivery-attempt">Registrar intento</button>' : ''}${this.any('delivery.operate', 'delivery.manage') && active && delivery.status !== 'blocked' ? '<button class="button danger" data-action="delivery-cause" data-kind="block">Bloquear</button>' : ''}${this.can('delivery.manage') && delivery.status === 'completed' ? '<button class="button" data-action="delivery-cause" data-kind="reopen">Reabrir</button>' : ''}${this.can('delivery_evidence.manage') ? '<button class="button" data-action="new-evidence">Registrar evidencia</button>' : ''}${this.can('orders.manage') ? `<button class="button danger" data-action="archive-order" data-id="${order.id}">Retirar del panel</button>` : ''}`;
    if (this.any('delivery_evidence.read', 'delivery_evidence.manage')) void this.renderEvidence(delivery.id);
  }

  private async renderEvidence(deliveryId: string): Promise<void> {
    try {
      const rows = await loadDeliveryEvidence(deliveryId);
      const root = this.optional<HTMLElement>('[data-evidence]');
      if (!root) return;
      root.innerHTML = rows.length ? table(['Tipo', 'Retención', 'Vence', 'Estado', ''], rows.map((item) => `<tr><td><span class="cell-title">${escapeHtml(item.evidence_kind)}</span><span class="cell-subtitle">${escapeHtml(item.purpose)}</span></td><td>${escapeHtml(item.retention_class)}</td><td>${formatDate(item.retention_due_at)}</td><td>${item.deleted_at ? badge('eliminada') : badge('vigente')}</td><td>${this.can('delivery_evidence.manage') && !item.deleted_at ? `<button class="button small danger" data-action="delete-evidence" data-id="${item.id}">Eliminar lógicamente</button>` : ''}</td></tr>`).join('')) : empty('Sin metadatos de evidencia');
    } catch (error) {
      this.toast(this.message(error), 'error');
    }
  }

  private renderSupport(): void {
    const rows = this.filtered(this.data as JsonRecord[]);
    this.content().innerHTML = rows.length ? table(['Asunto', 'Estado', 'Contacto', 'Apertura', ''], rows.map((item) => `<tr><td><span class="cell-title">${escapeHtml(item.subject)}</span><span class="cell-subtitle">${escapeHtml(item.purpose)}</span></td><td>${badge(item.status)}</td><td>${escapeHtml(item.contact_email ?? item.contact_phone ?? item.pseudonymous_reference ?? '—')}</td><td>${formatDate(item.opened_at)}</td><td><a class="button small" href="/admin/atencion/detalle?id=${item.id}">Abrir</a></td></tr>`).join('')) : empty('No hay solicitudes');
  }

  private renderSupportDetail(): void {
    const request = this.data.request;
    const messages = this.data.messages as JsonRecord[];
    const composer = request.status !== 'closed' && this.can('support.handle')
      ? `<form class="admin-support-composer" data-admin-support-reply><textarea name="body" required maxlength="4000" aria-label="Respuesta" placeholder="Escribe una respuesta como Mary..."></textarea><button class="button primary" type="submit">Enviar</button>${this.can('support.sensitive') ? '<label class="check-field"><input type="checkbox" name="sensitive"> Contenido sensible</label>' : ''}</form>`
      : '<div class="notice">La conversación está cerrada.</div>';
    this.content().innerHTML = `<div class="panel-body detail-stack"><div class="detail-grid"><div><span>Asunto</span><strong>${escapeHtml(request.subject)}</strong></div><div><span>Estado</span>${badge(request.status)}</div><div><span>Contacto</span><strong>${escapeHtml(request.contact_email ?? request.contact_phone ?? request.pseudonymous_reference ?? '—')}</strong></div><div><span>Apertura</span><strong>${formatDate(request.opened_at)}</strong></div></div><section class="admin-support-chat"><h2>Conversación con el cliente</h2><div class="message-list" data-admin-message-list>${messages.map((message) => `<article class="support-message ${message.direction}"><header><strong>${message.direction === 'incoming' ? 'Cliente' : 'Mary'}</strong><span>${formatDate(message.sent_at)}${message.is_sensitive ? ' · Sensible' : ''}</span></header><p>${escapeHtml(message.body)}</p></article>`).join('')}</div>${composer}</section></div>`;
    this.actions().innerHTML = `<a class="button" href="/admin/atencion">Volver</a>${this.can('support.handle') ? '<button class="button" data-action="support-status">Cambiar estado</button><button class="button danger" data-action="delete-support">Eliminar conversación</button>' : ''}`;
    requestAnimationFrame(() => {
      const list = this.optional<HTMLElement>('[data-admin-message-list]');
      if (list) list.scrollTop = list.scrollHeight;
    });
  }

  private renderAudit(): void {
    const term = this.optional<HTMLInputElement>('[data-search]')?.value.trim().toLowerCase() ?? '';
    const area = this.optional<HTMLSelectElement>('[data-status-filter]')?.value ?? '';
    const from = this.optional<HTMLInputElement>('[data-date-from]')?.value;
    const to = this.optional<HTMLInputElement>('[data-date-to]')?.value;
    const rows = (this.data as JsonRecord[]).filter((item) => {
      const date = String(item.occurred_at).slice(0, 10);
      return (!area || item.source_area === area) && (!from || date >= from) && (!to || date <= to) && (!term || JSON.stringify(item).toLowerCase().includes(term));
    });
    this.content().innerHTML = rows.length ? table(['Fecha', 'Área', 'Acción', 'Sujeto', 'Actor', 'Causa'], rows.map((item) => `<tr><td>${formatDate(item.occurred_at)}</td><td>${escapeHtml(item.source_area)}</td><td><span class="cell-title mono">${escapeHtml(item.action_code)}</span></td><td><span class="mono">${escapeHtml(item.subject_table)} · ${escapeHtml(item.subject_id)}</span></td><td><span class="mono">${escapeHtml(item.actor_operational_person_id ?? 'Sistema')}</span></td><td>${escapeHtml(item.cause ?? '—')}</td></tr>`).join('')) : empty('No hay eventos');
  }

  private async click(event: MouseEvent): Promise<void> {
    const button = (event.target as HTMLElement).closest<HTMLElement>('[data-action], [data-close-dialog]');
    if (!button) return;
    if (button.hasAttribute('data-close-dialog')) {
      this.dialog().close();
      return;
    }
    const action = button.dataset.action;
    const id = button.dataset.id;
    try {
      if (action === 'confirm-order' && id) await this.mutate(() => manageOrder(id, 'confirm'), 'Pedido confirmado.');
      if (action === 'authorize-preparation' && id) await this.mutate(() => authorizePreparation(id), 'Preparación autorizada.');
      if (action === 'cancel-order' && id) this.openCause('Cancelar pedido', (cause) => manageOrder(id, 'cancel', cause));
      if (action === 'verify-item' && id) await this.mutate(() => managePreparation(this.queryId(), 'verify', id), 'Partida verificada.');
      if (action === 'invalidate-item' && id) this.openCause('Invalidar verificación', (cause) => managePreparation(this.queryId(), 'invalidate', id, cause));
      if (action === 'prep-action') await this.mutate(() => managePreparation(this.queryId(), String(button.dataset.kind)), 'Preparación actualizada.');
      if (action === 'prep-cause') this.openCause('Actualizar preparación', (cause) => managePreparation(this.queryId(), String(button.dataset.kind), undefined, cause));
      if (action === 'create-delivery' && id) await this.mutate(() => createDelivery(id), 'Entrega creada.');
      if (action === 'new-provider') this.openProvider();
      if (action === 'assign-delivery') await this.openAssignment();
      if (action === 'custody-delivery') await this.openCustody();
      if (action === 'delivery-cause') this.openCause('Actualizar entrega', (cause) => setDeliveryState(this.queryId(), String(button.dataset.kind), cause));
      if (action === 'delivery-attempt') this.openAttempt();
      if (action === 'new-evidence') this.openEvidence();
      if (action === 'delete-evidence' && id) this.openCause('Eliminar evidencia lógicamente', (cause) => deleteDeliveryEvidence(id, cause));
      if (action === 'support-status') await this.openSupportStatus();
      if (action === 'delete-support') this.openDeleteSupport();
      if (action === 'archive-order' && id) this.openArchiveOrder(id);
    } catch (error) {
      this.toast(this.message(error), 'error');
    }
  }

  private openCause(title: string, handler: (cause: string) => Promise<unknown>): void {
    this.openDialog(title, '<label class="wide">Causa<textarea name="cause" required maxlength="1000"></textarea></label>', async (data) => {
      await handler(String(data.get('cause') ?? '').trim());
    });
  }

  private openProvider(): void {
    this.openDialog('Proveedor logístico', '<label>Nombre<input name="name" required maxlength="160"></label><label>Referencia externa<input name="reference" maxlength="160"></label>', async (data) => {
      await saveLogisticsProvider({ name: String(data.get('name')), externalReference: String(data.get('reference') ?? '') });
    });
  }

  private async openAssignment(): Promise<void> {
    const options = await loadDeliveryAssignmentOptions();
    const choices = [
      ...(options.people ?? []).map((item: JsonRecord) => `<option value="person:${item.id}">Persona · ${escapeHtml(item.display_name)}</option>`),
      ...(options.providers ?? []).map((item: JsonRecord) => `<option value="provider:${item.id}">Proveedor · ${escapeHtml(item.name)}</option>`),
    ].join('');
    this.openDialog('Asignar entrega', `<label class="wide">Responsable<select name="assignee" required><option value="">Seleccionar</option>${choices}</select></label><label>Referencia de persona externa<input name="external_reference" maxlength="160"></label><label class="wide">Causa<textarea name="cause" required></textarea></label>`, async (data) => {
      const [kind, id] = String(data.get('assignee')).split(':');
      await assignDelivery({ deliveryId: this.queryId(), operationalPersonId: kind === 'person' ? id : undefined, providerId: kind === 'provider' ? id : undefined, externalPersonReference: String(data.get('external_reference') ?? ''), cause: String(data.get('cause')) });
    });
  }

  private async openCustody(): Promise<void> {
    const options = this.can('delivery.manage') ? await loadDeliveryAssignmentOptions() : { people: [], providers: [] };
    const parties = `<option value="cherry_mary">Cherry Mary</option>${(options.people ?? []).map((item: JsonRecord) => `<option value="person:${item.id}">Persona · ${escapeHtml(item.display_name)}</option>`).join('')}${(options.providers ?? []).map((item: JsonRecord) => `<option value="provider:${item.id}">Proveedor · ${escapeHtml(item.name)}</option>`).join('')}<option value="external">Externo</option>`;
    this.openDialog('Evento de custodia', `<label>Evento<select name="event_kind"><option value="accepted">Aceptada</option><option value="transferred">Transferida</option><option value="returned">Devuelta</option><option value="released">Liberada</option></select></label><label>Origen<select name="from_party">${parties}</select></label><label>Destino<select name="to_party">${parties}</select></label><label>Referencia externa<input name="external_reference"></label><label class="wide">Causa<textarea name="cause"></textarea></label>`, async (data) => {
      const from = this.party(String(data.get('from_party')));
      const to = this.party(String(data.get('to_party')));
      await recordDeliveryCustody({ deliveryId: this.queryId(), eventKind: String(data.get('event_kind')), fromPartyKind: from.kind, fromOperationalPersonId: from.personId, fromProviderId: from.providerId, toPartyKind: to.kind, toOperationalPersonId: to.personId, toProviderId: to.providerId, externalPartyReference: String(data.get('external_reference') ?? ''), cause: String(data.get('cause') ?? '') });
    });
  }

  private party(value: string): { kind: string; personId?: string; providerId?: string } {
    if (value.startsWith('person:')) return { kind: 'operational_person', personId: value.slice(7) };
    if (value.startsWith('provider:')) return { kind: 'logistics_provider', providerId: value.slice(9) };
    if (value === 'external') return { kind: 'external_party' };
    return { kind: 'cherry_mary' };
  }

  private openAttempt(): void {
    this.openDialog('Intento de entrega', '<label>Resultado<select name="result"><option value="delivered">Entregado</option><option value="failed">Fallido</option><option value="rejected">Rechazado</option><option value="inaccessible">Inaccesible</option><option value="cancelled">Cancelado</option></select></label><label>Inicio<input type="datetime-local" name="started_at"></label><label class="wide">Confirmación de recepción<textarea name="receipt"></textarea></label><label class="wide">Causa de fallo<textarea name="failure"></textarea></label>', async (data) => {
      const started = String(data.get('started_at') ?? '');
      await registerDeliveryAttempt({ deliveryId: this.queryId(), result: String(data.get('result')), failureCause: String(data.get('failure') ?? ''), receiptConfirmation: String(data.get('receipt') ?? ''), startedAt: started ? new Date(started).toISOString() : undefined });
    });
  }

  private openEvidence(): void {
    const attempts = (this.data.attempts as JsonRecord[]).map((item) => `<option value="${item.id}">Intento ${item.attempt_number}</option>`).join('');
    this.openDialog('Metadatos de evidencia', `<label>Intento<select name="attempt_id"><option value="">Entrega general</option>${attempts}</select></label><label>Tipo<input name="kind" required maxlength="120"></label><label class="wide">Finalidad<textarea name="purpose" required maxlength="500"></textarea></label><label>Clase de retención<select name="retention"><option value="sensitive_no_dispute">Sin disputa</option><option value="dispute_evidence">Disputa</option><option value="exceptional_obligation">Obligación excepcional</option></select></label><label>Conservar hasta<input type="datetime-local" name="due" required></label><label class="wide">Contexto de disputa<textarea name="dispute"></textarea></label><label>Obligación documentada<input name="obligation"></label><label>Fecha de revisión<input type="datetime-local" name="review"></label><label>Referencia de contenido<input name="content_reference"></label><label>Tipo MIME<input name="mime"></label><label class="check-field wide"><input type="checkbox" name="sensitive" checked> Evidencia sensible</label>`, async (data) => {
      const due = String(data.get('due'));
      const review = String(data.get('review') ?? '');
      await registerDeliveryEvidence({ deliveryId: this.queryId(), attemptId: String(data.get('attempt_id') ?? ''), purpose: String(data.get('purpose')), evidenceKind: String(data.get('kind')), retentionClass: String(data.get('retention')), disputeContext: String(data.get('dispute') ?? ''), obligationReference: String(data.get('obligation') ?? ''), contentReference: String(data.get('content_reference') ?? ''), contentMimeType: String(data.get('mime') ?? ''), isSensitive: data.get('sensitive') === 'on', retentionDueAt: new Date(due).toISOString(), reviewAt: review ? new Date(review).toISOString() : null });
    });
  }

  private async submitSupportReply(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    const data = new FormData(form);
    this.busy(form, true);
    try {
      await respondSupport(this.queryId(), String(data.get('body') ?? '').trim(), data.get('sensitive') === 'on');
      await this.reload();
      this.toast('Respuesta enviada como Mary.', 'success');
    } catch (error) {
      this.toast(this.message(error), 'error');
    } finally {
      this.busy(form, false);
    }
  }

  private async openSupportStatus(): Promise<void> {
    const options = await loadSupportReferenceOptions();
    const request = this.data.request as JsonRecord;
    const currentReference = request.order_id
      ? `order:${request.order_id}`
      : request.preparation_id
        ? `preparation:${request.preparation_id}`
        : request.delivery_id
          ? `delivery:${request.delivery_id}`
          : 'keep';
    const optionRows = (kind: string, rows: JsonRecord[], label: string) => rows.length
      ? `<optgroup label="${label}">${rows.map((item) => `<option value="${kind}:${item.id}" ${currentReference === `${kind}:${item.id}` ? 'selected' : ''}>${escapeHtml(item.order_number)} · ${escapeHtml(String(item.status).replaceAll('_', ' '))}</option>`).join('')}</optgroup>`
      : '';
    const statuses = [
      ['open', 'Abierta'],
      ['in_attention', 'En atención'],
      ['resolved', 'Resuelta'],
      ['channelled', 'Canalizada'],
      ['closed', 'Cerrada'],
    ];
    this.openDialog('Estado de atención', `<label>Estado<select name="status">${statuses.map(([value, label]) => `<option value="${value}" ${request.status === value ? 'selected' : ''}>${label}</option>`).join('')}</select></label><label class="wide">Vínculo operativo<select name="reference"><option value="keep" ${currentReference === 'keep' ? 'selected' : ''}>Conservar vínculo actual</option><option value="none">Quitar vínculo</option>${optionRows('order', options.orders ?? [], 'Pedidos')}${optionRows('preparation', options.preparations ?? [], 'Preparaciones')}${optionRows('delivery', options.deliveries ?? [], 'Entregas')}</select></label><p class="notice wide">Al cerrar, escribe obligatoriamente el motivo. Una conversación cerrada puede reabrirse cambiando nuevamente su estado.</p><label class="wide">Motivo<textarea name="cause" maxlength="1000"></textarea></label>`, async (data) => {
      const reference = String(data.get('reference') ?? 'keep');
      const separator = reference.indexOf(':');
      await setSupportStatus({
        id: this.queryId(),
        status: String(data.get('status')),
        cause: String(data.get('cause') ?? ''),
        referenceKind: separator > 0 ? reference.slice(0, separator) : reference,
        referenceId: separator > 0 ? reference.slice(separator + 1) : '',
      });
    });
  }

  private openDeleteSupport(): void {
    this.openDialog('Eliminar conversación', '<p class="notice wide">La conversación desaparecerá del panel y del perfil del cliente. El historial se conservará internamente para auditoría.</p><label class="wide">Motivo de eliminación<textarea name="reason" required maxlength="1000"></textarea></label>', async (data) => {
      await deleteSupportRequest(this.queryId(), String(data.get('reason') ?? '').trim());
      window.setTimeout(() => { window.location.href = '/admin/atencion'; }, 0);
    });
  }

  private openArchiveOrder(orderId: string): void {
    const destination = this.section === 'order'
      ? '/admin/pedidos'
      : this.section === 'preparation-detail'
        ? '/admin/preparacion'
        : '/admin/entregas';
    this.openDialog('Retirar flujo del panel', '<p class="notice wide">El Pedido y sus etapas dejarán de aparecer en Pedidos, Preparación y Entregas. Los pagos, acciones y auditoría no se borrarán.</p><label class="wide">Inventario<select name="inventory" required><option value="restore">Sí, devolver los productos descontados al inventario</option><option value="keep">No, conservar el inventario como está</option></select></label><label class="wide">Motivo<textarea name="reason" required maxlength="1000"></textarea></label>', async (data) => {
      await archiveOrderWorkflow(orderId, data.get('inventory') === 'restore', String(data.get('reason') ?? '').trim());
      window.setTimeout(() => { window.location.href = destination; }, 0);
    });
  }

  private openDialog(title: string, fields: string, handler: SubmitHandler): void {
    this.el<HTMLElement>('[data-dialog-title]').textContent = title;
    this.el<HTMLElement>('[data-dialog-fields]').innerHTML = fields;
    this.submitHandler = handler;
    this.dialog().showModal();
  }

  private async submitDialog(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!this.submitHandler) return;
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    this.busy(form, true);
    try {
      await this.submitHandler(data);
      this.dialog().close();
      form.reset();
      await this.reload();
      this.toast('Cambio guardado.', 'success');
    } catch (error) {
      this.toast(this.message(error), 'error');
    } finally {
      this.busy(form, false);
    }
  }

  private async mutate(operation: () => Promise<unknown>, message: string): Promise<void> {
    this.el<HTMLElement>('[data-loading-state]').hidden = false;
    try {
      await operation();
      await this.reload();
      this.toast(message, 'success');
    } finally {
      this.el<HTMLElement>('[data-loading-state]').hidden = true;
    }
  }

  private content(): HTMLElement {
    return this.el<HTMLElement>('[data-content]');
  }

  private actions(): HTMLElement {
    return this.el<HTMLElement>('[data-page-actions]');
  }

  private dialog(): HTMLDialogElement {
    return this.el<HTMLDialogElement>('[data-operation-dialog]');
  }

  private busy(form: HTMLFormElement, value: boolean): void {
    form.querySelectorAll<HTMLInputElement | HTMLButtonElement | HTMLSelectElement | HTMLTextAreaElement>('input,button,select,textarea').forEach((element) => { element.disabled = value; });
  }

  private toast(message: string, tone: 'error' | 'success'): void {
    const toast = this.el<HTMLElement>('[data-toast]');
    toast.className = `toast notice ${tone}`;
    toast.textContent = message;
    toast.hidden = false;
    window.setTimeout(() => { toast.hidden = true; }, 5000);
  }

  private message(error: unknown): string {
    return error instanceof Error ? error.message : 'Ocurrió un error inesperado.';
  }
}

document.querySelectorAll<HTMLElement>('[data-operations-workspace]').forEach((root) => new OperationsWorkspace(root));
