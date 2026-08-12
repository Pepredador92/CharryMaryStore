import { currentSession } from '../services/auth';
import { loadRemoteCart, setRemoteCartItem, type RemoteCartLine } from '../services/cart';
import {
  formatMoney,
  loadPublicCatalog,
  packageAvailability,
  presentationAvailability,
  primaryResource,
  catalogResourceUrl,
  resolveCartTarget,
  type CatalogSnapshot,
  type Package,
  type Product,
} from '../services/catalog';
import { addGuestCartItem, readGuestCart, setGuestCartItem, type GuestCartItem } from '../stores/guest-cart';

type Mode = 'home' | 'products' | 'product-detail' | 'packages' | 'package-detail' | 'cart';

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

class Storefront {
  private root: HTMLElement;
  private mode: Mode;
  private snapshot: CatalogSnapshot | null = null;
  private quantityTimer: number | null = null;

  constructor(root: HTMLElement) {
    this.root = root;
    this.mode = root.dataset.mode as Mode;
    this.root.addEventListener('click', (event) => void this.handleClick(event));
    this.root.addEventListener('change', (event) => void this.handleChange(event));
    this.root.addEventListener('input', (event) => void this.handleCartQuantityInput(event));
    this.root.querySelector<HTMLInputElement>('[data-catalog-search]')?.addEventListener('input', () => this.renderListing());
    this.root.querySelector<HTMLSelectElement>('[data-classification-filter]')?.addEventListener('change', () => this.renderListing());
    void this.initialize();
  }

  private async initialize(): Promise<void> {
    try {
      this.snapshot = await loadPublicCatalog();
      if (this.mode === 'home') this.renderHome();
      else if (this.mode === 'products' || this.mode === 'packages') this.renderListing();
      else if (this.mode === 'product-detail') this.renderProductDetail();
      else if (this.mode === 'package-detail') this.renderPackageDetail();
      else await this.renderCart();
    } catch (error) {
      this.showError(error);
    }
  }

  private showError(error: unknown): void {
    const message = error instanceof Error ? error.message : 'No se pudo cargar esta vista.';
    const target = this.root.querySelector<HTMLElement>('[data-catalog-list], [data-detail-content], [data-cart-lines], [data-home-featured]');
    if (target) target.innerHTML = `<div class="state-box"><div><strong>No fue posible cargar</strong>${escapeHtml(message)}</div></div>`;
  }

  private showNotice(message: string, error = false): void {
    const notice = this.root.querySelector<HTMLElement>('[data-page-notice]');
    if (!notice) return;
    notice.textContent = message;
    notice.className = `shell-notice ${error ? 'error' : ''}`;
    notice.hidden = false;
    window.setTimeout(() => { notice.hidden = true; }, 4500);
  }

  private image(url: string | null, alt: string): string {
    return url
      ? `<img src="${escapeHtml(url)}" alt="${escapeHtml(alt)}" loading="lazy" />`
      : '<span class="catalog-placeholder"><strong>Cherry Mary</strong><span>Imagen proximamente</span></span>';
  }

  private productCard(product: Product): string {
    if (!this.snapshot) return '';
    const presentations = this.snapshot.presentations.filter((item) => item.product_id === product.id);
    const first = presentations[0];
    const price = first ? formatMoney(first.current_price_amount_minor, first.currency_code) : 'Proximamente';
    const totalAvailability = presentations.reduce((sum, item) => sum + presentationAvailability(this.snapshot!, item.id), 0);
    const resource = primaryResource(this.snapshot, 'product', product.id);
    return `<a class="catalog-card catalog-card-product" href="/productos/detalle?id=${product.id}">
      <span class="catalog-media">${this.image(catalogResourceUrl(resource), resource?.alt_text || product.name)}</span>
      <div class="catalog-card-body">
        <div class="catalog-card-copy"><h2>${escapeHtml(product.name)}</h2><p>${escapeHtml(product.description || 'Informacion comercial pendiente.')}</p></div>
        <div class="catalog-meta"><span class="price">${price}</span><span class="availability ${totalAvailability ? '' : 'out'}">${totalAvailability ? 'Disponible' : 'Sin disponibilidad'}</span></div>
      </div>
    </a>`;
  }

  private packageCard(itemPackage: Package): string {
    if (!this.snapshot) return '';
    const availability = packageAvailability(this.snapshot, itemPackage.id);
    const resource = primaryResource(this.snapshot, 'package', itemPackage.id);
    return `<article class="catalog-card catalog-card-package">
      <a class="catalog-media" href="/paquetes/detalle?id=${itemPackage.id}"><span class="catalog-card-tag">Paquete</span>${this.image(catalogResourceUrl(resource), resource?.alt_text || itemPackage.name)}</a>
      <div class="catalog-card-body">
        <div class="catalog-card-copy"><h2><a href="/paquetes/detalle?id=${itemPackage.id}">${escapeHtml(itemPackage.name)}</a></h2><p>${escapeHtml(itemPackage.description || 'Combinacion disponible por tiempo limitado.')}</p></div>
        <div class="catalog-meta"><span class="price">${formatMoney(itemPackage.current_price_amount_minor, itemPackage.currency_code)}</span><span class="availability ${availability ? '' : 'out'}">${availability ? 'Disponible' : 'Sin disponibilidad'}</span></div>
        <div class="card-actions"><a class="card-link" href="/paquetes/detalle?id=${itemPackage.id}">Ver detalle <span aria-hidden="true">&rarr;</span></a><button class="button primary compact" data-add-kind="package" data-add-id="${itemPackage.id}" ${availability ? '' : 'disabled'}>Agregar</button></div>
      </div>
    </article>`;
  }

  private renderHome(): void {
    if (!this.snapshot) return;
    const target = this.root.querySelector<HTMLElement>('[data-home-featured]');
    if (!target) return;
    const cards = [
      ...this.snapshot.products.slice(0, 2).map((item) => this.productCard(item)),
      ...this.snapshot.packages.slice(0, 1).map((item) => this.packageCard(item)),
    ];
    target.innerHTML = cards.length ? cards.join('') : '<div class="state-box"><div><strong>Catalogo en preparacion</strong>Los primeros articulos apareceran aqui cuando sean publicados.</div></div>';
  }

  private fillClassifications(): void {
    if (!this.snapshot) return;
    const select = this.root.querySelector<HTMLSelectElement>('[data-classification-filter]');
    if (!select || select.options.length > 1) return;
    select.insertAdjacentHTML('beforeend', this.snapshot.classifications.map((item) => `<option value="${item.id}">${escapeHtml(item.name)}</option>`).join(''));
  }

  private renderListing(): void {
    if (!this.snapshot) return;
    this.fillClassifications();
    const query = this.root.querySelector<HTMLInputElement>('[data-catalog-search]')?.value.trim().toLocaleLowerCase('es') ?? '';
    const classificationId = this.root.querySelector<HTMLSelectElement>('[data-classification-filter]')?.value ?? '';
    const assignedIds = new Set(
      this.snapshot.assignments
        .filter((item) => !classificationId || item.classification_id === classificationId)
        .map((item) => this.mode === 'products' ? item.product_id : item.package_id)
        .filter(Boolean),
    );
    const cards = this.mode === 'products'
      ? this.snapshot.products
          .filter((item) => (!query || `${item.name} ${item.description ?? ''}`.toLocaleLowerCase('es').includes(query)) && (!classificationId || assignedIds.has(item.id)))
          .map((item) => this.productCard(item))
      : this.snapshot.packages
          .filter((item) => (!query || `${item.name} ${item.description ?? ''}`.toLocaleLowerCase('es').includes(query)) && (!classificationId || assignedIds.has(item.id)))
          .map((item) => this.packageCard(item));
    const target = this.root.querySelector<HTMLElement>('[data-catalog-list]');
    if (target) target.innerHTML = cards.length ? cards.join('') : '<div class="state-box"><div><strong>Sin resultados</strong>Prueba con otra busqueda o clasificacion.</div></div>';
  }

  private queryId(): string | null {
    return new URLSearchParams(window.location.search).get('id');
  }

  private renderProductDetail(): void {
    if (!this.snapshot) return;
    const product = this.snapshot.products.find((item) => item.id === this.queryId());
    const target = this.root.querySelector<HTMLElement>('[data-detail-content]');
    if (!target) return;
    if (!product) {
      target.innerHTML = '<div class="state-box"><div><strong>Producto no disponible</strong>Puede haber sido desactivado o el enlace ya no es vigente.</div></div>';
      return;
    }
    const presentations = this.snapshot.presentations.filter((item) => item.product_id === product.id);
    const selected = presentations[0];
    const resource = primaryResource(this.snapshot, 'product', product.id);
    target.innerHTML = `<div class="detail-layout">
      <div class="detail-media">${this.image(catalogResourceUrl(resource), resource?.alt_text || product.name)}</div>
      <div class="detail-copy">
        <div><span class="badge">Producto</span><h1>${escapeHtml(product.name)}</h1></div>
        <p>${escapeHtml(product.description || 'Informacion comercial pendiente.')}</p>
        ${product.usage_instructions ? `<div class="detail-note"><strong>Instrucciones</strong><p>${escapeHtml(product.usage_instructions)}</p></div>` : ''}
        ${product.warnings ? `<div class="notice"><strong>Advertencias</strong><p>${escapeHtml(product.warnings)}</p></div>` : ''}
        ${presentations.length ? `<label>Presentacion<select data-detail-presentation>${presentations.map((item) => `<option value="${item.id}">${escapeHtml(item.variant_label || item.sku)}</option>`).join('')}</select></label>
          <div class="catalog-meta"><span class="price" data-detail-price>${selected ? formatMoney(selected.current_price_amount_minor, selected.currency_code) : ''}</span><span class="availability" data-detail-availability></span></div>
          <button class="button primary" data-add-selected>Agregar al carrito</button>` : '<div class="notice error">No hay Presentaciones vendibles.</div>'}
      </div>
    </div>`;
    this.updatePresentationSelection();
  }

  private updatePresentationSelection(): void {
    if (!this.snapshot) return;
    const select = this.root.querySelector<HTMLSelectElement>('[data-detail-presentation]');
    const presentation = this.snapshot.presentations.find((item) => item.id === select?.value);
    if (!presentation) return;
    const availability = presentationAvailability(this.snapshot, presentation.id);
    const price = this.root.querySelector<HTMLElement>('[data-detail-price]');
    const status = this.root.querySelector<HTMLElement>('[data-detail-availability]');
    const add = this.root.querySelector<HTMLButtonElement>('[data-add-selected]');
    if (price) price.textContent = formatMoney(presentation.current_price_amount_minor, presentation.currency_code);
    if (status) {
      status.textContent = availability ? `${availability} disponibles` : 'Sin disponibilidad';
      status.classList.toggle('out', availability === 0);
    }
    if (add) add.disabled = availability === 0;
  }

  private renderPackageDetail(): void {
    if (!this.snapshot) return;
    const itemPackage = this.snapshot.packages.find((item) => item.id === this.queryId());
    const target = this.root.querySelector<HTMLElement>('[data-detail-content]');
    if (!target) return;
    if (!itemPackage) {
      target.innerHTML = '<div class="state-box"><div><strong>Paquete no disponible</strong>Puede haber vencido o haber sido desactivado.</div></div>';
      return;
    }
    const components = this.snapshot.components.filter((item) => item.package_id === itemPackage.id && item.is_active);
    const availability = packageAvailability(this.snapshot, itemPackage.id);
    const resource = primaryResource(this.snapshot, 'package', itemPackage.id);
    target.innerHTML = `<div class="detail-layout">
      <div class="detail-media">${this.image(catalogResourceUrl(resource), resource?.alt_text || itemPackage.name)}</div>
      <div class="detail-copy">
        <div><span class="badge">Paquete</span><h1>${escapeHtml(itemPackage.name)}</h1></div>
        <p>${escapeHtml(itemPackage.description || 'Combinacion de Presentaciones vigentes.')}</p>
        <div><strong>Incluye</strong><ul class="component-list">${components.map((component) => {
          const presentation = this.snapshot!.presentations.find((item) => item.id === component.presentation_id);
          const product = this.snapshot!.products.find((item) => item.id === presentation?.product_id);
          return `<li>${component.quantity} x ${escapeHtml(product?.name || 'Producto')} ${presentation?.variant_label ? `- ${escapeHtml(presentation.variant_label)}` : ''}</li>`;
        }).join('')}</ul></div>
        <div class="catalog-meta"><span class="price">${formatMoney(itemPackage.current_price_amount_minor, itemPackage.currency_code)}</span><span class="availability ${availability ? '' : 'out'}">${availability ? `${availability} disponibles` : 'Sin disponibilidad'}</span></div>
        <button class="button primary" data-add-kind="package" data-add-id="${itemPackage.id}" ${availability ? '' : 'disabled'}>Agregar al carrito</button>
      </div>
    </div>`;
  }

  private async add(kind: 'presentation' | 'package', id: string): Promise<void> {
    const target = this.snapshot ? resolveCartTarget(this.snapshot, kind, id) : null;
    if (!target?.sellable) {
      this.showNotice('Este articulo ya no tiene disponibilidad.', true);
      return;
    }
    const session = await currentSession();
    if (session) await setRemoteCartItem(kind, id, 1, 'add');
    else addGuestCartItem(kind, id, 1);
    this.showNotice(`${target.name} se agrego al carrito.`);
  }

  private async handleClick(event: Event): Promise<void> {
    const button = (event.target as Element).closest<HTMLButtonElement>('button');
    if (!button) return;
    const kind = button.dataset.addKind as 'presentation' | 'package' | undefined;
    const id = button.dataset.addId;
    if (kind && id) {
      button.disabled = true;
      try { await this.add(kind, id); } catch (error) { this.showNotice(error instanceof Error ? error.message : 'No se pudo agregar.', true); }
      button.disabled = false;
      return;
    }
    if (button.matches('[data-add-selected]')) {
      const presentationId = this.root.querySelector<HTMLSelectElement>('[data-detail-presentation]')?.value;
      if (!presentationId) return;
      button.disabled = true;
      try { await this.add('presentation', presentationId); } catch (error) { this.showNotice(error instanceof Error ? error.message : 'No se pudo agregar.', true); }
      button.disabled = false;
      return;
    }
    if (button.dataset.cartRemoveKind && button.dataset.cartRemoveId) {
      await this.changeCartItem(button.dataset.cartRemoveKind as 'presentation' | 'package', button.dataset.cartRemoveId, 0);
    }
  }

  private async handleChange(event: Event): Promise<void> {
    const target = event.target as HTMLInputElement | HTMLSelectElement;
    if (target.matches('[data-detail-presentation]')) this.updatePresentationSelection();
  }

  private handleCartQuantityInput(event: Event): void {
    const target = event.target as HTMLInputElement;
    if (!target.dataset.cartQuantityKind || !target.dataset.cartQuantityId || !target.value) return;
    if (this.quantityTimer !== null) window.clearTimeout(this.quantityTimer);
    const kind = target.dataset.cartQuantityKind as 'presentation' | 'package';
    const id = target.dataset.cartQuantityId;
    const quantity = Number(target.value);
    this.quantityTimer = window.setTimeout(() => {
      this.quantityTimer = null;
      void this.changeCartItem(kind, id, quantity);
    }, 350);
  }

  private async changeCartItem(kind: 'presentation' | 'package', id: string, quantity: number): Promise<void> {
    try {
      const session = await currentSession();
      if (session) await setRemoteCartItem(kind, id, quantity);
      else setGuestCartItem(kind, id, quantity);
      await this.renderCart();
    } catch (error) {
      this.showNotice(error instanceof Error ? error.message : 'No se pudo actualizar el carrito.', true);
    }
  }

  private async renderCart(): Promise<void> {
    if (!this.snapshot) return;
    const session = await currentSession();
    let items: GuestCartItem[] = [];
    if (session) {
      const cart = await loadRemoteCart();
      items = cart.lines.map((line: RemoteCartLine) => ({
        kind: line.line_kind,
        targetId: line.presentation_id ?? line.package_id ?? '',
        quantity: line.quantity,
      }));
    } else {
      items = readGuestCart().items;
    }
    const resolved = items.map((item) => ({ item, target: resolveCartTarget(this.snapshot!, item.kind, item.targetId) }));
    const lines = this.root.querySelector<HTMLElement>('[data-cart-lines]');
    const checkout = this.root.querySelector<HTMLAnchorElement>('[data-checkout-link]');
    const total = resolved.reduce((sum, row) => sum + (row.target?.priceAmountMinor ?? 0) * row.item.quantity, 0);
    this.root.querySelectorAll<HTMLElement>('[data-cart-total]').forEach((element) => { element.textContent = formatMoney(total); });
    if (checkout) {
      const blocked = items.length === 0 || resolved.some((row) => !row.target?.sellable);
      checkout.setAttribute('aria-disabled', String(blocked));
      if (blocked) checkout.removeAttribute('href');
      else checkout.href = '/checkout';
    }
    if (!lines) return;
    if (!items.length) {
      lines.innerHTML = '<div class="state-box"><div><strong>Tu carrito esta vacio</strong>Agrega una Presentacion o un Paquete para continuar.</div></div>';
      return;
    }
    lines.innerHTML = resolved.map(({ item, target }) => {
      if (!target) return `<article class="cart-line"><div class="cart-thumb"></div><div><h3>Articulo no disponible</h3><p>Ya no aparece en el catalogo vigente.</p></div><span></span><button class="button danger" data-cart-remove-kind="${item.kind}" data-cart-remove-id="${item.targetId}">Quitar</button></article>`;
      return `<article class="cart-line">
        ${target.imageUrl ? `<img class="cart-thumb" src="${escapeHtml(target.imageUrl)}" alt="" />` : '<div class="cart-thumb"></div>'}
        <div><h3>${escapeHtml(target.name)}</h3><p>${escapeHtml(target.detail)} · ${formatMoney(target.priceAmountMinor, target.currencyCode)}${target.sellable ? '' : ' · Sin disponibilidad'}</p></div>
        <label>Cantidad<input type="number" min="1" max="99" value="${item.quantity}" data-cart-quantity-kind="${item.kind}" data-cart-quantity-id="${item.targetId}" /></label>
        <button class="button danger" data-cart-remove-kind="${item.kind}" data-cart-remove-id="${item.targetId}">Quitar</button>
      </article>`;
    }).join('');
  }
}

document.querySelectorAll<HTMLElement>('[data-storefront-app]').forEach((root) => new Storefront(root));
