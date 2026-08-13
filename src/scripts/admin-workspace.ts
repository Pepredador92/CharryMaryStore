import { supabase } from '../lib/supabase/client';
import {
  adjustInventory,
  archiveProduct,
  createClassificationAssignment,
  deleteCatalogResource,
  deleteClassificationAssignment,
  deletePackageComponent,
  deletePresentation,
  deleteProduct,
  getCatalogResourceUrl,
  getCurrentCapabilities,
  loadCatalogSnapshot,
  replaceCatalogResource,
  retireInventoryPresentation,
  saveClassification,
  savePackage,
  savePackageComponent,
  savePresentation,
  saveProduct,
  setPackageActive,
  setPresentationActive,
  setPrimaryCatalogResource,
  setProductActive,
  updateCatalogResource,
  uploadCatalogResource,
  type CatalogResource,
  type CatalogSnapshot,
  type Classification,
  type Package,
  type Presentation,
  type Product,
} from '../lib/admin/catalog';

type Section = 'dashboard' | 'products' | 'packages' | 'inventory' | 'classifications';
type OwnerType = 'product' | 'presentation' | 'package';

const moneyFormatter = new Intl.NumberFormat('es-MX', {
  style: 'currency',
  currency: 'MXN',
});
const dateFormatter = new Intl.DateTimeFormat('es-MX', {
  dateStyle: 'medium',
  timeStyle: 'short',
});

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function money(amountMinor: number, currencyCode = 'MXN'): string {
  try {
    return new Intl.NumberFormat('es-MX', { style: 'currency', currency: currencyCode }).format(amountMinor / 100);
  } catch {
    return moneyFormatter.format(amountMinor / 100);
  }
}

function formatDate(value: string | null): string {
  return value ? dateFormatter.format(new Date(value)) : 'Sin límite';
}

function toDateTimeLocal(value: string | null): string {
  if (!value) return '';
  const date = new Date(value);
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function fromDateTimeLocal(value: FormDataEntryValue | null): string | null {
  return value ? new Date(String(value)).toISOString() : null;
}

function statusBadge(isActive: boolean, archivedAt?: string | null): string {
  if (archivedAt) return '<span class="badge archived">Archivado</span>';
  return isActive
    ? '<span class="badge active">Activo</span>'
    : '<span class="badge inactive">Inactivo</span>';
}

function emptyState(title: string, detail: string): string {
  return `<div class="state-box"><div><strong>${escapeHtml(title)}</strong>${escapeHtml(detail)}</div></div>`;
}

class AdminWorkspace {
  private root: HTMLElement;
  private section: Section;
  private snapshot: CatalogSnapshot | null = null;
  private capabilities = new Set<string>();
  private resourceOwner: { type: OwnerType; id: string; title: string } | null = null;
  private replacementResourceId: string | null = null;

  constructor(root: HTMLElement) {
    this.root = root;
    this.section = root.dataset.section as Section;
    this.bindEvents();
    void this.initialize();
  }

  private element<T extends Element>(selector: string): T {
    const element = this.root.querySelector<T>(selector);
    if (!element) throw new Error(`Falta el elemento administrativo ${selector}`);
    return element;
  }

  private optional<T extends Element>(selector: string): T | null {
    return this.root.querySelector<T>(selector);
  }

  private async initialize(): Promise<void> {
    const { data, error } = await supabase.auth.getSession();
    if (error) {
      this.showAuth(error.message);
      return;
    }
    if (!data.session) {
      this.showAuth();
      return;
    }
    await this.activateSession(data.session.user.email ?? 'Cuenta operativa');
  }

  private bindEvents(): void {
    this.optional<HTMLFormElement>('[data-auth-form]')?.addEventListener('submit', (event) => void this.signIn(event));
    document.querySelector<HTMLButtonElement>('[data-sign-out]')?.addEventListener('click', () => void this.signOut());
    this.root.addEventListener('click', (event) => void this.handleClick(event));

    this.optional<HTMLInputElement>('[data-product-search]')?.addEventListener('input', () => this.renderProducts());
    this.optional<HTMLInputElement>('[data-package-search]')?.addEventListener('input', () => this.renderPackages());
    this.optional<HTMLInputElement>('[data-inventory-search]')?.addEventListener('input', () => this.renderInventory());

    this.optional<HTMLFormElement>('[data-product-form]')?.addEventListener('submit', (event) => void this.submitProduct(event));
    this.optional<HTMLFormElement>('[data-presentation-form]')?.addEventListener('submit', (event) => void this.submitPresentation(event));
    this.optional<HTMLFormElement>('[data-package-form]')?.addEventListener('submit', (event) => void this.submitPackage(event));
    this.optional<HTMLFormElement>('[data-component-form]')?.addEventListener('submit', (event) => void this.submitComponent(event));
    this.optional<HTMLFormElement>('[data-classification-form]')?.addEventListener('submit', (event) => void this.submitClassification(event));
    this.optional<HTMLFormElement>('[data-assignment-form]')?.addEventListener('submit', (event) => void this.submitAssignment(event));
    this.optional<HTMLSelectElement>('[data-assignment-form] [name="target_type"]')?.addEventListener('change', () => this.populateAssignmentTargets());
    this.optional<HTMLFormElement>('[data-inventory-form]')?.addEventListener('submit', (event) => void this.submitInventory(event));
    this.optional<HTMLFormElement>('[data-inventory-retire-form]')?.addEventListener('submit', (event) => void this.submitInventoryRetirement(event));
    this.optional<HTMLFormElement>('[data-resource-form]')?.addEventListener('submit', (event) => void this.submitResource(event));
    this.optional<HTMLInputElement>('[data-resource-replacement]')?.addEventListener('change', (event) => void this.replaceResource(event));
  }

  private async signIn(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    this.setFormBusy(form, true);
    const result = await supabase.auth.signInWithPassword({
      email: String(data.get('email') ?? '').trim(),
      password: String(data.get('password') ?? ''),
    });
    this.setFormBusy(form, false);
    if (result.error || !result.data.session) {
      this.showAuth(result.error?.message ?? 'No fue posible iniciar sesión.');
      return;
    }
    await this.activateSession(result.data.user.email ?? 'Cuenta operativa');
  }

  private async signOut(): Promise<void> {
    await supabase.auth.signOut();
    this.snapshot = null;
    this.capabilities.clear();
    this.showAuth();
  }

  private showAuth(message?: string): void {
    this.element<HTMLElement>('[data-loading-state]').hidden = true;
    this.element<HTMLElement>('[data-access-state]').hidden = true;
    this.element<HTMLElement>('[data-workspace-content]').hidden = true;
    this.element<HTMLElement>('[data-auth-panel]').hidden = false;
    const error = this.element<HTMLElement>('[data-auth-error]');
    error.hidden = !message;
    error.textContent = message ?? '';
    const signOut = document.querySelector<HTMLButtonElement>('[data-sign-out]');
    const email = document.querySelector<HTMLElement>('[data-session-email]');
    if (signOut) signOut.hidden = true;
    if (email) email.textContent = 'Sesión no iniciada';
  }

  private async activateSession(emailAddress: string): Promise<void> {
    this.element<HTMLElement>('[data-auth-panel]').hidden = true;
    this.element<HTMLElement>('[data-loading-state]').hidden = false;
    const email = document.querySelector<HTMLElement>('[data-session-email]');
    const signOut = document.querySelector<HTMLButtonElement>('[data-sign-out]');
    if (email) email.textContent = emailAddress;
    if (signOut) signOut.hidden = false;

    try {
      this.capabilities = await getCurrentCapabilities();
      if (!this.canAccessSection()) {
        this.element<HTMLElement>('[data-loading-state]').hidden = true;
        this.element<HTMLElement>('[data-access-state]').hidden = false;
        return;
      }
      await this.reload();
      this.element<HTMLElement>('[data-loading-state]').hidden = true;
      this.element<HTMLElement>('[data-access-state]').hidden = true;
      this.element<HTMLElement>('[data-workspace-content]').hidden = false;
    } catch (error) {
      this.element<HTMLElement>('[data-loading-state]').hidden = true;
      this.showToast(this.message(error), 'error');
    }
  }

  private canAccessSection(): boolean {
    if (this.section === 'inventory') return this.can('inventory.read') || this.can('inventory.adjust');
    if (this.section === 'dashboard') {
      return this.can('catalog.read') || this.can('catalog.manage') || this.can('inventory.read') || this.can('inventory.adjust');
    }
    return this.can('catalog.read') || this.can('catalog.manage');
  }

  private can(code: string): boolean {
    return this.capabilities.has(code);
  }

  private get canManageCatalog(): boolean {
    return this.can('catalog.manage');
  }

  private get canAdjustInventory(): boolean {
    return this.can('inventory.adjust');
  }

  private async reload(): Promise<void> {
    this.snapshot = await loadCatalogSnapshot();
    this.render();
  }

  private render(): void {
    if (!this.snapshot) return;
    if (this.section === 'dashboard') this.renderDashboard();
    if (this.section === 'products') this.renderProducts();
    if (this.section === 'packages') this.renderPackages();
    if (this.section === 'inventory') this.renderInventory();
    if (this.section === 'classifications') this.renderClassifications();
    this.applyCapabilityControls();
  }

  private applyCapabilityControls(): void {
    this.root.querySelectorAll<HTMLButtonElement>('[data-create-action], [data-create-presentation]').forEach((button) => {
      button.disabled = !this.canManageCatalog;
      button.title = this.canManageCatalog ? '' : 'Requiere catalog.manage';
    });
  }

  private renderDashboard(): void {
    if (!this.snapshot) return;
    const activeProducts = this.snapshot.products.filter((item) => item.is_active && !item.archived_at).length;
    const activePresentations = this.snapshot.presentations.filter((item) => item.is_active && !item.archived_at).length;
    const activePackages = this.snapshot.packages.filter((item) => item.is_active && !item.archived_at).length;
    const imageCount = this.snapshot.resources.filter((item) => item.is_active).length;
    this.element<HTMLElement>('[data-dashboard-stats]').innerHTML = `
      <article class="stat accent"><span>Productos activos</span><strong>${activeProducts}</strong></article>
      <article class="stat"><span>Presentaciones activas</span><strong>${activePresentations}</strong></article>
      <article class="stat"><span>Paquetes activos</span><strong>${activePackages}</strong></article>
      <article class="stat"><span>Imágenes activas</span><strong>${imageCount}</strong></article>`;

    const withoutPresentation = this.snapshot.products.filter(
      (product) => !this.snapshot?.presentations.some((presentation) => presentation.product_id === product.id),
    ).length;
    const withoutImage = this.snapshot.products.filter(
      (product) => !this.snapshot?.resources.some((resource) => resource.product_id === product.id && resource.is_active),
    ).length;
    const packagesWithoutComponents = this.snapshot.packages.filter(
      (item) => !this.snapshot?.components.some((component) => component.package_id === item.id && component.is_active),
    ).length;
    this.element<HTMLElement>('[data-dashboard-summary]').innerHTML = `
      <div class="component-list">
        <div class="component-row"><span>Productos sin Presentación</span><strong>${withoutPresentation}</strong><a class="button small" href="/admin/productos">Revisar</a></div>
        <div class="component-row"><span>Productos sin imagen activa</span><strong>${withoutImage}</strong><a class="button small" href="/admin/productos">Revisar</a></div>
        <div class="component-row"><span>Paquetes sin componentes activos</span><strong>${packagesWithoutComponents}</strong><a class="button small" href="/admin/paquetes">Revisar</a></div>
      </div>`;

    const canReadInventory = this.can('inventory.read') || this.canAdjustInventory;
    const lowStock = this.snapshot.presentations
      .map((presentation) => ({
        presentation,
        quantity: this.inventoryQuantity(presentation.id),
      }))
      .filter(({ quantity }) => quantity <= 5)
      .sort((a, b) => a.quantity - b.quantity)
      .slice(0, 8);
    this.element<HTMLElement>('[data-low-stock]').innerHTML = !canReadInventory
      ? emptyState('Acceso restringido', 'Requiere inventory.read o inventory.adjust.')
      : lowStock.length
      ? `<div class="component-list">${lowStock
          .map(({ presentation, quantity }) => `<div class="component-row"><span><strong>${escapeHtml(presentation.sku)}</strong><span class="cell-subtitle">${escapeHtml(presentation.variant_label || 'Sin variante')}</span></span><strong>${quantity}</strong><a class="button small" href="/admin/inventario">Ver</a></div>`)
          .join('')}</div>`
      : emptyState('Inventario saludable', 'No hay Presentaciones con existencias bajas.');
  }

  private renderProducts(): void {
    if (!this.snapshot) return;
    const term = this.optional<HTMLInputElement>('[data-product-search]')?.value.trim().toLowerCase() ?? '';
    const products = this.snapshot.products.filter((product) => {
      if (!term) return true;
      const presentations = this.snapshot?.presentations.filter((item) => item.product_id === product.id) ?? [];
      return [product.name, ...presentations.flatMap((item) => [item.sku, item.variant_label ?? ''])].some((value) =>
        value.toLowerCase().includes(term),
      );
    });
    const productTable = this.element<HTMLElement>('[data-products-table]');
    productTable.innerHTML = products.length
      ? `<table class="data-table"><thead><tr><th>Producto</th><th>Presentaciones</th><th>Imágenes</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>${products
          .map((product) => {
            const presentations = this.snapshot?.presentations.filter((item) => item.product_id === product.id).length ?? 0;
            const images = this.snapshot?.resources.filter((item) => item.product_id === product.id).length ?? 0;
            return `<tr>
              <td><span class="cell-title">${escapeHtml(product.name)}</span><span class="cell-subtitle">${escapeHtml(product.description || 'Sin descripción')}</span></td>
              <td>${presentations}</td><td>${images}</td><td>${statusBadge(product.is_active, product.archived_at)}</td>
              <td><div class="inline-actions">
                <button class="button small" data-action="edit-product" data-id="${product.id}" ${this.canManageCatalog ? '' : 'disabled'}>Editar</button>
                <button class="button small" data-action="toggle-product" data-id="${product.id}" ${product.archived_at || !this.canManageCatalog ? 'disabled' : ''}>${product.is_active ? 'Desactivar' : 'Activar'}</button>
                <button class="button small" data-action="resources" data-owner-type="product" data-id="${product.id}">Imágenes</button>
                <button class="button small danger" data-action="archive-product" data-id="${product.id}" ${product.archived_at || !this.canManageCatalog ? 'disabled' : ''}>Archivar</button>
                <button class="button small danger" data-action="delete-product" data-id="${product.id}" ${this.canManageCatalog ? '' : 'disabled'}>Eliminar</button>
              </div></td></tr>`;
          })
          .join('')}</tbody></table>`
      : emptyState('Sin productos', term ? 'No hay resultados para la búsqueda.' : 'Crea el primer Producto del catálogo.');

    const presentations = this.snapshot.presentations.filter((presentation) => {
      if (!term) return true;
      const product = this.product(presentation.product_id);
      return [presentation.sku, presentation.variant_label ?? '', product?.name ?? ''].some((value) => value.toLowerCase().includes(term));
    });
    const presentationTable = this.element<HTMLElement>('[data-presentations-table]');
    presentationTable.innerHTML = presentations.length
      ? `<table class="data-table"><thead><tr><th>SKU / Variante</th><th>Producto</th><th>Precio</th><th>Existencias</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>${presentations
          .map((presentation) => `<tr>
            <td><span class="cell-title mono">${escapeHtml(presentation.sku)}</span><span class="cell-subtitle">${escapeHtml(presentation.variant_label || 'Sin variante')}</span></td>
            <td>${escapeHtml(this.product(presentation.product_id)?.name || 'Producto no disponible')}</td>
            <td>${money(presentation.current_price_amount_minor, presentation.currency_code)}</td>
            <td>${this.inventoryQuantity(presentation.id)}</td><td>${statusBadge(presentation.is_active, presentation.archived_at)}</td>
            <td><div class="inline-actions">
              <button class="button small" data-action="edit-presentation" data-id="${presentation.id}" ${this.canManageCatalog ? '' : 'disabled'}>Editar</button>
              <button class="button small" data-action="toggle-presentation" data-id="${presentation.id}" ${presentation.archived_at || !this.canManageCatalog ? 'disabled' : ''}>${presentation.is_active ? 'Desactivar' : 'Activar'}</button>
              <button class="button small" data-action="resources" data-owner-type="presentation" data-id="${presentation.id}">Imágenes</button>
              <button class="button small danger" data-action="delete-presentation" data-id="${presentation.id}" ${this.canManageCatalog ? '' : 'disabled'}>Eliminar</button>
            </div></td></tr>`)
          .join('')}</tbody></table>`
      : emptyState('Sin presentaciones', 'Crea una Presentación asociada a un Producto.');
  }

  private renderPackages(): void {
    if (!this.snapshot) return;
    const term = this.optional<HTMLInputElement>('[data-package-search]')?.value.trim().toLowerCase() ?? '';
    const packages = this.snapshot.packages.filter((item) => item.name.toLowerCase().includes(term));
    this.element<HTMLElement>('[data-packages-table]').innerHTML = packages.length
      ? `<table class="data-table"><thead><tr><th>Paquete</th><th>Precio</th><th>Vigencia</th><th>Componentes</th><th>Disponibles</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>${packages
          .map((item) => {
            const components = this.snapshot?.components.filter((component) => component.package_id === item.id && component.is_active) ?? [];
            return `<tr><td><span class="cell-title">${escapeHtml(item.name)}</span><span class="cell-subtitle">${escapeHtml(item.description || 'Sin descripción')}</span></td>
              <td>${money(item.current_price_amount_minor, item.currency_code)}</td>
              <td><span class="cell-title">${formatDate(item.valid_from)}</span><span class="cell-subtitle">Hasta ${formatDate(item.valid_until)}</span></td>
              <td>${components.length}</td><td><strong>${this.packageAvailability(item.id) ?? 'Sin acceso'}</strong></td><td>${statusBadge(item.is_active, item.archived_at)}</td>
              <td><div class="inline-actions"><button class="button small" data-action="edit-package" data-id="${item.id}" ${this.canManageCatalog ? '' : 'disabled'}>Editar</button><button class="button small" data-action="toggle-package" data-id="${item.id}" ${!this.canManageCatalog ? 'disabled' : ''}>${item.is_active ? 'Desactivar' : 'Activar'}</button><button class="button small" data-action="resources" data-owner-type="package" data-id="${item.id}">Imágenes</button></div></td></tr>`;
          })
          .join('')}</tbody></table>`
      : emptyState('Sin paquetes', term ? 'No hay resultados para la búsqueda.' : 'Crea el primer Paquete comercial.');
  }

  private renderInventory(): void {
    if (!this.snapshot) return;
    const term = this.optional<HTMLInputElement>('[data-inventory-search]')?.value.trim().toLowerCase() ?? '';
    const presentations = this.snapshot.presentations.filter((presentation) => {
      const product = this.product(presentation.product_id);
      return !presentation.archived_at
        && (!term || [presentation.sku, presentation.variant_label ?? '', product?.name ?? ''].some((value) => value.toLowerCase().includes(term)));
    });
    this.element<HTMLElement>('[data-inventory-table]').innerHTML = presentations.length
      ? `<table class="data-table"><thead><tr><th>Presentación</th><th>Producto</th><th>Existencias</th><th>Actualizado</th><th>Acción</th></tr></thead><tbody>${presentations
          .map((presentation) => {
            const inventory = this.snapshot?.inventory.find((item) => item.presentation_id === presentation.id);
            return `<tr><td><span class="cell-title mono">${escapeHtml(presentation.sku)}</span><span class="cell-subtitle">${escapeHtml(presentation.variant_label || 'Sin variante')}</span></td><td>${escapeHtml(this.product(presentation.product_id)?.name || '')}</td><td><strong>${inventory?.on_hand_quantity ?? 0}</strong></td><td>${inventory ? formatDate(inventory.updated_at) : 'Sin movimientos'}</td><td><div class="inline-actions"><button class="button small primary" data-action="adjust-inventory" data-id="${presentation.id}" ${this.canAdjustInventory ? '' : 'disabled'}>Cambiar cantidad</button><button class="button small danger" data-action="retire-inventory" data-id="${presentation.id}" ${this.canAdjustInventory && this.canManageCatalog ? '' : 'disabled'}>Eliminar del inventario</button></div></td></tr>`;
          })
          .join('')}</tbody></table>`
      : emptyState('Sin presentaciones', 'Crea Presentaciones antes de registrar inventario.');

    this.element<HTMLElement>('[data-movements-table]').innerHTML = this.snapshot.movements.length
      ? `<table class="data-table"><thead><tr><th>Fecha</th><th>Presentación</th><th>Tipo</th><th>Cambio</th><th>Causa</th></tr></thead><tbody>${this.snapshot.movements
          .map((movement) => `<tr><td>${formatDate(movement.occurred_at)}</td><td><span class="cell-title mono">${escapeHtml(this.presentation(movement.presentation_id)?.sku || movement.presentation_id)}</span></td><td>${escapeHtml(movement.movement_kind === 'stock_entry' ? 'Entrada de stock' : 'Ajuste manual')}</td><td><strong>${movement.quantity_delta > 0 ? '+' : ''}${movement.quantity_delta}</strong></td><td>${escapeHtml(movement.cause)}</td></tr>`)
          .join('')}</tbody></table>`
      : emptyState('Sin movimientos', 'El historial aparecerá después de la primera entrada o ajuste.');
  }

  private renderClassifications(): void {
    if (!this.snapshot) return;
    this.element<HTMLElement>('[data-classifications-table]').innerHTML = this.snapshot.classifications.length
      ? `<table class="data-table"><thead><tr><th>Clasificación</th><th>Superior</th><th>Estado</th><th>Acción</th></tr></thead><tbody>${this.snapshot.classifications
          .map((item) => `<tr><td><span class="cell-title">${escapeHtml(item.name)}</span><span class="cell-subtitle">${escapeHtml(item.description || 'Sin descripción')}</span></td><td>${escapeHtml(item.parent_id ? this.classification(item.parent_id)?.name || 'No disponible' : 'Raíz')}</td><td>${statusBadge(item.is_active)}</td><td><button class="button small" data-action="edit-classification" data-id="${item.id}" ${this.canManageCatalog ? '' : 'disabled'}>Editar</button></td></tr>`)
          .join('')}</tbody></table>`
      : emptyState('Sin clasificaciones', 'Crea la primera clasificación comercial.');
    this.populateAssignmentForm();
    this.renderAssignments();
  }

  private renderAssignments(): void {
    if (!this.snapshot) return;
    const list = this.element<HTMLElement>('[data-assignments-list]');
    list.innerHTML = this.snapshot.assignments.length
      ? this.snapshot.assignments
          .map((assignment) => {
            const classification = this.classification(assignment.classification_id)?.name ?? 'Clasificación no disponible';
            const target = assignment.product_id
              ? this.product(assignment.product_id)?.name ?? 'Producto no disponible'
              : this.package(assignment.package_id ?? '')?.name ?? 'Paquete no disponible';
            return `<div class="component-row"><span><strong>${escapeHtml(classification)}</strong><span class="cell-subtitle">${escapeHtml(target)}</span></span><span class="badge">${assignment.product_id ? 'Producto' : 'Paquete'}</span><button class="button small danger" data-action="delete-assignment" data-id="${assignment.id}" ${this.canManageCatalog ? '' : 'disabled'}>Quitar</button></div>`;
          })
          .join('')
      : emptyState('Sin asignaciones', 'Asocia clasificaciones a Productos o Paquetes.');
  }

  private async handleClick(event: MouseEvent): Promise<void> {
    const button = (event.target as Element).closest<HTMLButtonElement>('button');
    if (!button || button.disabled) return;
    if (button.matches('[data-close-dialog]')) {
      button.closest<HTMLDialogElement>('dialog')?.close();
      return;
    }
    if (button.matches('[data-create-action]')) {
      if (this.section === 'products') this.openProduct();
      if (this.section === 'packages') this.openPackage();
      if (this.section === 'classifications') this.openClassification();
      return;
    }
    if (button.matches('[data-create-presentation]')) {
      this.openPresentation();
      return;
    }

    const action = button.dataset.action;
    const id = button.dataset.id;
    if (!action || !id || !this.snapshot) return;

    if (action === 'edit-product') this.openProduct(this.product(id));
    if (action === 'edit-presentation') this.openPresentation(this.presentation(id));
    if (action === 'edit-package') this.openPackage(this.package(id));
    if (action === 'edit-classification') this.openClassification(this.classification(id));
    if (action === 'adjust-inventory') this.openInventory(id);
    if (action === 'retire-inventory') this.openInventoryRetirement(id);
    if (action === 'resources') {
      const ownerType = button.dataset.ownerType as OwnerType;
      this.openResources(ownerType, id);
    }
    if (action === 'toggle-product') {
      const item = this.product(id);
      if (item) await this.runMutation(() => setProductActive(id, !item.is_active), 'Estado del producto actualizado.');
    }
    if (action === 'archive-product') {
      if (window.confirm('¿Archivar este Producto? Permanecerá en el historial y dejará de estar disponible.')) {
        await this.runMutation(() => archiveProduct(id), 'Producto archivado.');
      }
    }
    if (action === 'delete-product') {
      const item = this.product(id);
      if (item && window.confirm(`¿Eliminar “${item.name}”?\n\nDejará de aparecer en el panel y en la tienda. El historial de pedidos o inventario se conservará cuando exista.`)) {
        await this.runMutation(() => deleteProduct(id), 'Producto eliminado.');
      }
    }
    if (action === 'delete-presentation') {
      const item = this.presentation(id);
      if (item && window.confirm(`¿Eliminar la Presentación “${item.sku}”?\n\nDejará de aparecer en Productos, Inventario y la tienda. Su historial se conservará cuando exista.`)) {
        await this.runMutation(() => deletePresentation(id), 'Presentación eliminada.');
      }
    }
    if (action === 'toggle-presentation') {
      const item = this.presentation(id);
      if (item) await this.runMutation(() => setPresentationActive(id, !item.is_active), 'Estado de la Presentación actualizado.');
    }
    if (action === 'toggle-package') {
      const item = this.package(id);
      if (item) await this.runMutation(() => setPackageActive(id, !item.is_active), 'Estado del Paquete actualizado.');
    }
    if (action === 'delete-component') {
      if (window.confirm('¿Quitar este componente del Paquete?')) {
        await this.runMutation(() => deletePackageComponent(id), 'Componente eliminado.', () => this.renderPackageComponents());
      }
    }
    if (action === 'delete-assignment') {
      if (window.confirm('¿Quitar esta asignación comercial?')) {
        await this.runMutation(() => deleteClassificationAssignment(id), 'Asignación eliminada.');
      }
    }
    if (action === 'set-primary-resource') await this.runMutation(() => setPrimaryCatalogResource(id), 'Imagen principal actualizada.', () => this.renderResources());
    if (action === 'toggle-resource') {
      const resource = this.resource(id);
      if (resource) await this.runMutation(() => updateCatalogResource(id, { is_active: !resource.is_active }), 'Estado de la imagen actualizado.', () => this.renderResources());
    }
    if (action === 'save-resource') {
      const card = button.closest<HTMLElement>('[data-resource-card]');
      const altText = card?.querySelector<HTMLInputElement>('[data-resource-alt]')?.value.trim() || null;
      const sortOrder = Number(card?.querySelector<HTMLInputElement>('[data-resource-order]')?.value ?? 0);
      await this.runMutation(() => updateCatalogResource(id, { alt_text: altText, sort_order: sortOrder }), 'Recurso actualizado.', () => this.renderResources());
    }
    if (action === 'replace-resource') {
      this.replacementResourceId = id;
      this.element<HTMLInputElement>('[data-resource-replacement]').click();
    }
    if (action === 'delete-resource') {
      const resource = this.resource(id);
      if (resource && window.confirm('¿Eliminar esta imagen y su archivo del catálogo?')) {
        await this.runMutation(() => deleteCatalogResource(resource), 'Imagen eliminada.', () => this.renderResources());
      }
    }
  }

  private openProduct(product?: Product): void {
    const form = this.element<HTMLFormElement>('[data-product-form]');
    form.reset();
    this.setValue(form, 'id', product?.id ?? '');
    this.setValue(form, 'name', product?.name ?? '');
    this.setValue(form, 'description', product?.description ?? '');
    this.setValue(form, 'usage_instructions', product?.usage_instructions ?? '');
    this.setValue(form, 'warnings', product?.warnings ?? '');
    this.setChecked(form, 'is_active', product?.is_active ?? true);
    this.element<HTMLElement>('[data-product-dialog-title]').textContent = product ? 'Editar Producto' : 'Nuevo Producto';
    this.element<HTMLDialogElement>('[data-product-dialog]').showModal();
  }

  private openPresentation(presentation?: Presentation): void {
    if (!this.snapshot?.products.length) {
      this.showToast('Primero crea un Producto.', 'error');
      return;
    }
    const form = this.element<HTMLFormElement>('[data-presentation-form]');
    form.reset();
    const select = form.elements.namedItem('product_id') as HTMLSelectElement;
    select.innerHTML = this.snapshot.products.map((item) => `<option value="${item.id}">${escapeHtml(item.name)}</option>`).join('');
    this.setValue(form, 'id', presentation?.id ?? '');
    this.setValue(form, 'product_id', presentation?.product_id ?? this.snapshot.products[0].id);
    this.setValue(form, 'sku', presentation?.sku ?? '');
    this.setValue(form, 'variant_label', presentation?.variant_label ?? '');
    this.setValue(form, 'price', presentation ? String(presentation.current_price_amount_minor / 100) : '');
    this.setValue(form, 'currency_code', presentation?.currency_code ?? 'MXN');
    this.setValue(form, 'attributes', presentation?.attributes ? JSON.stringify(presentation.attributes, null, 2) : '');
    this.setChecked(form, 'is_active', presentation?.is_active ?? true);
    this.element<HTMLElement>('[data-presentation-dialog-title]').textContent = presentation ? 'Editar Presentación' : 'Nueva Presentación';
    this.element<HTMLDialogElement>('[data-presentation-dialog]').showModal();
  }

  private openPackage(item?: Package): void {
    const form = this.element<HTMLFormElement>('[data-package-form]');
    form.reset();
    this.setValue(form, 'id', item?.id ?? '');
    this.setValue(form, 'name', item?.name ?? '');
    this.setValue(form, 'description', item?.description ?? '');
    this.setValue(form, 'price', item ? String(item.current_price_amount_minor / 100) : '');
    this.setValue(form, 'currency_code', item?.currency_code ?? 'MXN');
    this.setValue(form, 'valid_from', toDateTimeLocal(item?.valid_from ?? null));
    this.setValue(form, 'valid_until', toDateTimeLocal(item?.valid_until ?? null));
    this.setChecked(form, 'is_active', item?.is_active ?? true);
    this.element<HTMLElement>('[data-package-dialog-title]').textContent = item ? 'Editar Paquete' : 'Nuevo Paquete';
    const componentsSection = this.element<HTMLElement>('[data-package-components-section]');
    componentsSection.hidden = !item;
    if (item) {
      const componentForm = this.element<HTMLFormElement>('[data-component-form]');
      componentForm.reset();
      this.setValue(componentForm, 'package_id', item.id);
      const presentationSelect = componentForm.elements.namedItem('presentation_id') as HTMLSelectElement;
      presentationSelect.innerHTML = (this.snapshot?.presentations ?? [])
        .map((presentation) => `<option value="${presentation.id}">${escapeHtml(presentation.sku)} · ${escapeHtml(this.product(presentation.product_id)?.name ?? '')}</option>`)
        .join('');
      this.renderPackageComponents(item.id);
    }
    this.element<HTMLDialogElement>('[data-package-dialog]').showModal();
  }

  private renderPackageComponents(packageId?: string): void {
    if (!this.snapshot) return;
    const id = packageId ?? this.element<HTMLInputElement>('[data-component-form] [name="package_id"]').value;
    const components = this.snapshot.components.filter((item) => item.package_id === id);
    this.element<HTMLElement>('[data-package-components-list]').innerHTML = components.length
      ? components
          .map((component) => {
            const presentation = this.presentation(component.presentation_id);
            return `<div class="component-row"><span><strong>${escapeHtml(presentation?.sku || 'Presentación no disponible')}</strong><span class="cell-subtitle">${escapeHtml(presentation?.variant_label || '')}</span></span><strong>× ${component.quantity}</strong><button class="button small danger" data-action="delete-component" data-id="${component.id}" ${this.canManageCatalog ? '' : 'disabled'}>Quitar</button></div>`;
          })
          .join('')
      : emptyState('Sin componentes', 'Agrega Presentaciones y cantidades al Paquete.');
  }

  private openClassification(item?: Classification): void {
    const form = this.element<HTMLFormElement>('[data-classification-form]');
    form.reset();
    const parent = form.elements.namedItem('parent_id') as HTMLSelectElement;
    parent.innerHTML = `<option value="">Sin clasificación superior</option>${(this.snapshot?.classifications ?? [])
      .filter((candidate) => candidate.id !== item?.id)
      .map((candidate) => `<option value="${candidate.id}">${escapeHtml(candidate.name)}</option>`)
      .join('')}`;
    this.setValue(form, 'id', item?.id ?? '');
    this.setValue(form, 'name', item?.name ?? '');
    this.setValue(form, 'description', item?.description ?? '');
    this.setValue(form, 'parent_id', item?.parent_id ?? '');
    this.setChecked(form, 'is_active', item?.is_active ?? true);
    this.element<HTMLElement>('[data-classification-dialog-title]').textContent = item ? 'Editar Clasificación' : 'Nueva Clasificación';
    this.element<HTMLDialogElement>('[data-classification-dialog]').showModal();
  }

  private openInventory(presentationId: string): void {
    const presentation = this.presentation(presentationId);
    if (!presentation) return;
    const form = this.element<HTMLFormElement>('[data-inventory-form]');
    form.reset();
    this.setValue(form, 'presentation_id', presentation.id);
    this.setValue(form, 'target_quantity', String(this.inventoryQuantity(presentation.id)));
    this.element<HTMLElement>('[data-inventory-presentation]').textContent = `${presentation.sku} · ${this.product(presentation.product_id)?.name ?? ''} · Existencias actuales: ${this.inventoryQuantity(presentation.id)}`;
    this.element<HTMLDialogElement>('[data-inventory-dialog]').showModal();
  }

  private openInventoryRetirement(presentationId: string): void {
    const presentation = this.presentation(presentationId);
    if (!presentation) return;
    const form = this.element<HTMLFormElement>('[data-inventory-retire-form]');
    form.reset();
    this.setValue(form, 'presentation_id', presentation.id);
    this.element<HTMLElement>('[data-inventory-retire-presentation]').textContent = `${presentation.sku} · ${this.product(presentation.product_id)?.name ?? ''} · Se retirarán ${this.inventoryQuantity(presentation.id)} unidad(es).`;
    this.element<HTMLDialogElement>('[data-inventory-retire-dialog]').showModal();
  }

  private openResources(type: OwnerType, id: string): void {
    const title = type === 'product'
      ? this.product(id)?.name
      : type === 'presentation'
        ? this.presentation(id)?.sku
        : this.package(id)?.name;
    this.resourceOwner = { type, id, title: title ?? 'Elemento del catálogo' };
    const form = this.element<HTMLFormElement>('[data-resource-form]');
    form.reset();
    this.setValue(form, 'owner_type', type);
    this.setValue(form, 'owner_id', id);
    const matching = this.ownerResources();
    this.setValue(form, 'sort_order', String(matching.length));
    this.element<HTMLElement>('[data-resource-dialog-title]').textContent = `Imágenes · ${this.resourceOwner.title}`;
    this.renderResources();
    this.element<HTMLDialogElement>('[data-resource-dialog]').showModal();
  }

  private renderResources(): void {
    const resources = this.ownerResources();
    this.element<HTMLElement>('[data-resources-list]').innerHTML = resources.length
      ? resources
          .map((resource) => `<article class="resource-card" data-resource-card>
            <img src="${escapeHtml(getCatalogResourceUrl(resource.source_reference))}" alt="${escapeHtml(resource.alt_text || '')}" loading="lazy" />
            <div class="resource-card-body">
              <p>${resource.is_primary ? '<span class="badge active">Principal</span> ' : ''}${resource.is_active ? 'Visible' : 'Inactiva'}</p>
              <label>Texto alternativo<input data-resource-alt value="${escapeHtml(resource.alt_text || '')}" /></label>
              <label>Orden<input data-resource-order type="number" min="0" step="1" value="${resource.sort_order}" /></label>
              <div class="inline-actions">
                <button class="button small" data-action="save-resource" data-id="${resource.id}" ${this.canManageCatalog ? '' : 'disabled'}>Guardar</button>
                <button class="button small" data-action="set-primary-resource" data-id="${resource.id}" ${resource.is_primary || !this.canManageCatalog ? 'disabled' : ''}>Principal</button>
                <button class="button small" data-action="toggle-resource" data-id="${resource.id}" ${!this.canManageCatalog ? 'disabled' : ''}>${resource.is_active ? 'Desactivar' : 'Activar'}</button>
                <button class="button small" data-action="replace-resource" data-id="${resource.id}" ${!this.canManageCatalog ? 'disabled' : ''}>Reemplazar</button>
                <button class="button small danger" data-action="delete-resource" data-id="${resource.id}" ${!this.canManageCatalog ? 'disabled' : ''}>Eliminar</button>
              </div>
            </div>
          </article>`)
          .join('')
      : emptyState('Sin imágenes', 'Sube la primera imagen comercial de este elemento.');
  }

  private async submitProduct(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    await this.runFormMutation(form, () => saveProduct({
      id: String(data.get('id') || '') || undefined,
      name: String(data.get('name') || ''),
      description: String(data.get('description') || ''),
      usage_instructions: String(data.get('usage_instructions') || ''),
      warnings: String(data.get('warnings') || ''),
      is_active: data.get('is_active') === 'on',
    }), 'Producto guardado.', () => this.element<HTMLDialogElement>('[data-product-dialog]').close());
  }

  private async submitPresentation(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    let attributes: Record<string, unknown> | null = null;
    const rawAttributes = String(data.get('attributes') || '').trim();
    if (rawAttributes) {
      try {
        attributes = JSON.parse(rawAttributes) as Record<string, unknown>;
      } catch {
        this.showToast('Los atributos deben ser un objeto JSON válido.', 'error');
        return;
      }
    }
    await this.runFormMutation(form, () => savePresentation({
      id: String(data.get('id') || '') || undefined,
      product_id: String(data.get('product_id')),
      sku: String(data.get('sku') || ''),
      variant_label: String(data.get('variant_label') || ''),
      attributes,
      current_price_amount_minor: Math.round(Number(data.get('price')) * 100),
      currency_code: String(data.get('currency_code') || 'MXN'),
      is_active: data.get('is_active') === 'on',
    }), 'Presentación guardada.', () => this.element<HTMLDialogElement>('[data-presentation-dialog]').close());
  }

  private async submitPackage(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    let savedId = '';
    await this.runFormMutation(form, async () => {
      savedId = await savePackage({
        id: String(data.get('id') || '') || undefined,
        name: String(data.get('name') || ''),
        description: String(data.get('description') || ''),
        current_price_amount_minor: Math.round(Number(data.get('price')) * 100),
        currency_code: String(data.get('currency_code') || 'MXN'),
        valid_from: fromDateTimeLocal(data.get('valid_from')),
        valid_until: fromDateTimeLocal(data.get('valid_until')),
        is_active: data.get('is_active') === 'on',
      });
    }, 'Paquete guardado.', () => {
      const saved = this.package(savedId);
      if (saved) {
        this.element<HTMLDialogElement>('[data-package-dialog]').close();
        this.openPackage(saved);
      }
    });
  }

  private async submitComponent(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    await this.runFormMutation(form, () => savePackageComponent({
      package_id: String(data.get('package_id')),
      presentation_id: String(data.get('presentation_id')),
      quantity: Number(data.get('quantity')),
      is_active: data.get('is_active') === 'on',
    }), 'Componente agregado.', () => {
      form.reset();
      this.setValue(form, 'package_id', String(data.get('package_id')));
      this.setChecked(form, 'is_active', true);
      this.renderPackageComponents(String(data.get('package_id')));
    });
  }

  private async submitClassification(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    await this.runFormMutation(form, () => saveClassification({
      id: String(data.get('id') || '') || undefined,
      name: String(data.get('name') || ''),
      description: String(data.get('description') || ''),
      parent_id: String(data.get('parent_id') || '') || null,
      is_active: data.get('is_active') === 'on',
    }), 'Clasificación guardada.', () => this.element<HTMLDialogElement>('[data-classification-dialog]').close());
  }

  private async submitAssignment(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const targetType = String(data.get('target_type'));
    await this.runFormMutation(form, () => createClassificationAssignment({
      classification_id: String(data.get('classification_id')),
      product_id: targetType === 'product' ? String(data.get('target_id')) : null,
      package_id: targetType === 'package' ? String(data.get('target_id')) : null,
    }), 'Asignación creada.', () => this.renderAssignments());
  }

  private async submitInventory(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const presentationId = String(data.get('presentation_id'));
    const currentQuantity = this.inventoryQuantity(presentationId);
    const targetQuantity = Number(data.get('target_quantity'));
    if (!Number.isSafeInteger(targetQuantity) || targetQuantity < 0) {
      this.showToast('La cantidad final debe ser un número entero igual o mayor que cero.', 'error');
      return;
    }
    if (targetQuantity === currentQuantity) {
      this.showToast('La cantidad final es igual a la existencia actual.', 'error');
      return;
    }
    await this.runFormMutation(form, () => adjustInventory({
      presentationId,
      quantityDelta: targetQuantity - currentQuantity,
      movementKind: 'manual_adjustment',
      cause: String(data.get('cause') || ''),
    }), 'Existencias actualizadas.', () => this.element<HTMLDialogElement>('[data-inventory-dialog]').close());
  }

  private async submitInventoryRetirement(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    await this.runFormMutation(form, () => retireInventoryPresentation(
      String(data.get('presentation_id')),
      String(data.get('cause') || ''),
    ), 'Producto eliminado del inventario.', () => this.element<HTMLDialogElement>('[data-inventory-retire-dialog]').close());
  }

  private async submitResource(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const file = data.get('file');
    if (!(file instanceof File) || !file.size) {
      this.showToast('Selecciona una imagen.', 'error');
      return;
    }
    await this.runFormMutation(form, () => uploadCatalogResource({
      ownerType: String(data.get('owner_type')) as OwnerType,
      ownerId: String(data.get('owner_id')),
      file,
      altText: String(data.get('alt_text') || ''),
      sortOrder: Number(data.get('sort_order')),
    }), 'Imagen subida.', () => {
      const owner = this.resourceOwner;
      form.reset();
      if (owner) {
        this.setValue(form, 'owner_type', owner.type);
        this.setValue(form, 'owner_id', owner.id);
        this.setValue(form, 'sort_order', String(this.ownerResources().length));
      }
      this.renderResources();
    });
  }

  private async replaceResource(event: Event): Promise<void> {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    const resource = this.replacementResourceId ? this.resource(this.replacementResourceId) : undefined;
    input.value = '';
    this.replacementResourceId = null;
    if (!file || !resource) return;
    await this.runMutation(() => replaceCatalogResource(resource, file), 'Imagen reemplazada.', () => this.renderResources());
  }

  private populateAssignmentForm(): void {
    if (!this.snapshot) return;
    const form = this.element<HTMLFormElement>('[data-assignment-form]');
    const classifications = form.elements.namedItem('classification_id') as HTMLSelectElement;
    classifications.innerHTML = this.snapshot.classifications
      .map((item) => `<option value="${item.id}">${escapeHtml(item.name)}</option>`)
      .join('');
    this.populateAssignmentTargets();
    form.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLButtonElement>('input, select, button').forEach((element) => {
      element.disabled = !this.canManageCatalog;
    });
  }

  private populateAssignmentTargets(): void {
    if (!this.snapshot) return;
    const form = this.optional<HTMLFormElement>('[data-assignment-form]');
    if (!form) return;
    const targetType = (form.elements.namedItem('target_type') as HTMLSelectElement).value;
    const target = form.elements.namedItem('target_id') as HTMLSelectElement;
    target.innerHTML = targetType === 'product'
      ? this.snapshot.products.map((item) => `<option value="${item.id}">${escapeHtml(item.name)}</option>`).join('')
      : this.snapshot.packages.map((item) => `<option value="${item.id}">${escapeHtml(item.name)}</option>`).join('');
  }

  private async runFormMutation(form: HTMLFormElement, action: () => Promise<unknown>, success: string, after?: () => void): Promise<void> {
    this.setFormBusy(form, true);
    await this.runMutation(action, success, after);
    this.setFormBusy(form, false);
  }

  private async runMutation(action: () => Promise<unknown>, success: string, after?: () => void): Promise<void> {
    try {
      await action();
      await this.reload();
      after?.();
      this.showToast(success, 'success');
    } catch (error) {
      this.showToast(this.message(error), 'error');
    }
  }

  private setFormBusy(form: HTMLFormElement, busy: boolean): void {
    form.setAttribute('aria-busy', String(busy));
    form.querySelectorAll<HTMLButtonElement>('button').forEach((button) => {
      const busyText = button.dataset.busyText;
      if (busyText) {
        if (busy) {
          button.dataset.idleText = button.textContent ?? '';
          button.textContent = busyText;
        } else if (button.dataset.idleText !== undefined) {
          button.textContent = button.dataset.idleText;
          delete button.dataset.idleText;
        }
      }
      button.disabled = busy;
    });
  }

  private showToast(message: string, tone: 'success' | 'error'): void {
    const toast = this.element<HTMLElement>('[data-toast]');
    toast.textContent = message;
    toast.className = `notice toast ${tone}`;
    toast.hidden = false;
    window.setTimeout(() => {
      toast.hidden = true;
    }, 5200);
  }

  private message(error: unknown): string {
    return error instanceof Error ? error.message : 'Ocurrió un error inesperado.';
  }

  private setValue(form: HTMLFormElement, name: string, value: string): void {
    const field = form.elements.namedItem(name) as HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | null;
    if (field) field.value = value;
  }

  private setChecked(form: HTMLFormElement, name: string, checked: boolean): void {
    const field = form.elements.namedItem(name) as HTMLInputElement | null;
    if (field) field.checked = checked;
  }

  private product(id: string): Product | undefined {
    return this.snapshot?.products.find((item) => item.id === id);
  }

  private presentation(id: string): Presentation | undefined {
    return this.snapshot?.presentations.find((item) => item.id === id);
  }

  private package(id: string): Package | undefined {
    return this.snapshot?.packages.find((item) => item.id === id);
  }

  private classification(id: string): Classification | undefined {
    return this.snapshot?.classifications.find((item) => item.id === id);
  }

  private resource(id: string): CatalogResource | undefined {
    return this.snapshot?.resources.find((item) => item.id === id);
  }

  private inventoryQuantity(presentationId: string): number {
    return this.snapshot?.inventory.find((item) => item.presentation_id === presentationId)?.on_hand_quantity ?? 0;
  }

  private packageAvailability(packageId: string): number | null {
    if (!this.can('inventory.read') && !this.canAdjustInventory) return null;
    const components = this.snapshot?.components.filter((item) => item.package_id === packageId && item.is_active) ?? [];
    if (!components.length) return 0;
    return Math.min(...components.map((component) => Math.floor(this.inventoryQuantity(component.presentation_id) / component.quantity)));
  }

  private ownerResources(): CatalogResource[] {
    if (!this.resourceOwner || !this.snapshot) return [];
    const key = `${this.resourceOwner.type}_id` as 'product_id' | 'presentation_id' | 'package_id';
    return this.snapshot.resources
      .filter((resource) => resource[key] === this.resourceOwner?.id)
      .sort((a, b) => a.sort_order - b.sort_order || a.created_at.localeCompare(b.created_at));
  }
}

document.querySelectorAll<HTMLElement>('[data-admin-workspace]').forEach((root) => new AdminWorkspace(root));
