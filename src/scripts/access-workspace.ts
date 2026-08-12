import { getCurrentCapabilities } from '../lib/admin/catalog';
import {
  createOperationalAccess,
  loadOperationalAccess,
  setOperationalAccessCapabilities,
  setOperationalAccessStatus,
  type OperationalAccess,
  type OperationalAccessSnapshot,
  type OperationalCapability,
} from '../lib/admin/access';
import { supabase } from '../lib/supabase/client';

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function badge(status: string): string {
  const tone = status === 'active' ? 'active' : status === 'suspended' ? 'inactive' : 'archived';
  return `<span class="badge ${tone}">${escapeHtml(status)}</span>`;
}

class AccessWorkspace {
  private root: HTMLElement;
  private snapshot: OperationalAccessSnapshot | null = null;
  private currentCapabilities = new Set<string>();

  constructor(root: HTMLElement) {
    this.root = root;
    this.bind();
    void this.initialize();
  }

  private el<T extends Element>(selector: string): T {
    const element = this.root.querySelector<T>(selector);
    if (!element) throw new Error(`Falta ${selector}`);
    return element;
  }

  private bind(): void {
    this.el<HTMLFormElement>('[data-auth-form]').addEventListener('submit', (event) => void this.signIn(event));
    document.querySelector<HTMLButtonElement>('[data-sign-out]')?.addEventListener('click', () => void this.signOut());
    this.el<HTMLButtonElement>('[data-create-access]').addEventListener('click', () => this.openCreate());
    this.el<HTMLInputElement>('[data-access-search]').addEventListener('input', () => this.renderTable());
    this.el<HTMLFormElement>('[data-create-form]').addEventListener('submit', (event) => void this.submitCreate(event));
    this.el<HTMLFormElement>('[data-capability-form]').addEventListener('submit', (event) => void this.submitCapabilities(event));
    this.el<HTMLFormElement>('[data-status-form]').addEventListener('submit', (event) => void this.submitStatus(event));
    this.root.addEventListener('click', (event) => this.handleClick(event));
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
    this.currentCapabilities.clear();
    this.snapshot = null;
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
      this.currentCapabilities = await getCurrentCapabilities();
      if (!this.canRead()) {
        this.el<HTMLElement>('[data-loading-state]').hidden = true;
        this.el<HTMLElement>('[data-access-state]').hidden = false;
        return;
      }
      await this.reload();
      this.el<HTMLElement>('[data-loading-state]').hidden = true;
      this.el<HTMLElement>('[data-access-state]').hidden = true;
      this.el<HTMLElement>('[data-workspace-content]').hidden = false;
      this.el<HTMLButtonElement>('[data-create-access]').hidden = !this.canManage();
    } catch (error) {
      this.el<HTMLElement>('[data-loading-state]').hidden = true;
      this.el<HTMLElement>('[data-access-state]').hidden = false;
      this.toast(this.message(error), 'error');
    }
  }

  private canRead(): boolean {
    return this.currentCapabilities.has('access.read') || this.currentCapabilities.has('access.manage');
  }

  private canManage(): boolean {
    return this.currentCapabilities.has('access.manage');
  }

  private async reload(): Promise<void> {
    this.snapshot = await loadOperationalAccess();
    this.renderStats();
    this.renderTable();
  }

  private renderStats(): void {
    if (!this.snapshot) return;
    const active = this.snapshot.accounts.filter((account) => account.account_status === 'active').length;
    const suspended = this.snapshot.accounts.filter((account) => account.account_status === 'suspended').length;
    this.el<HTMLElement>('[data-access-stats]').innerHTML = [
      ['Cuentas activas', active, 'accent'],
      ['Suspendidas', suspended, ''],
      ['Capacidades disponibles', this.snapshot.capabilities.length, ''],
    ].map(([label, value, tone]) => (
      `<div class="stat ${tone}"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`
    )).join('');
  }

  private renderTable(): void {
    if (!this.snapshot) return;
    const query = this.el<HTMLInputElement>('[data-access-search]').value.trim().toLocaleLowerCase('es-MX');
    const accounts = this.snapshot.accounts.filter((account) => (
      `${account.display_name} ${account.email} ${account.internal_reference}`.toLocaleLowerCase('es-MX').includes(query)
    ));

    if (!accounts.length) {
      this.el<HTMLElement>('[data-access-table]').innerHTML = '<div class="state-box"><div><strong>Sin accesos</strong>No hay cuentas que coincidan con la búsqueda.</div></div>';
      return;
    }

    const rows = accounts.map((account) => {
      const capabilities = account.capability_codes.length
        ? `<div class="capability-summary">${account.capability_codes.map((code) => `<span>${escapeHtml(code)}</span>`).join('')}</div>`
        : '<span class="cell-subtitle">Sin capacidades</span>';
      const actions = this.canManage()
        ? `<div class="inline-actions">
            <button class="button small" type="button" data-edit-capabilities="${account.account_id}">Capacidades</button>
            ${account.is_current
              ? '<span class="cell-subtitle">Sesión actual</span>'
              : account.account_status === 'active'
                ? `<button class="button danger small" type="button" data-change-status="${account.account_id}" data-next-status="suspended">Suspender</button>`
                : account.account_status === 'suspended'
                  ? `<button class="button small" type="button" data-change-status="${account.account_id}" data-next-status="active">Reactivar</button>`
                  : ''}
          </div>`
        : '';
      return `<tr>
        <td><span class="cell-title">${escapeHtml(account.display_name)}</span><span class="cell-subtitle">${escapeHtml(account.internal_reference)}</span></td>
        <td>${escapeHtml(account.email)}</td>
        <td>${badge(account.account_status)}</td>
        <td>${capabilities}</td>
        <td>${actions}</td>
      </tr>`;
    }).join('');

    this.el<HTMLElement>('[data-access-table]').innerHTML = `<table class="data-table access-table">
      <thead><tr><th>Persona</th><th>Correo</th><th>Estado</th><th>Capacidades</th><th>Acciones</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>`;
  }

  private handleClick(event: Event): void {
    const button = (event.target as Element).closest<HTMLButtonElement>('button');
    if (!button) return;
    if (button.matches('[data-close-dialog]')) {
      button.closest<HTMLDialogElement>('dialog')?.close();
      return;
    }
    if (button.matches('[data-select-all]')) {
      button.closest('form')?.querySelectorAll<HTMLInputElement>('input[name="capability_code"]').forEach((input) => { input.checked = true; });
      return;
    }
    if (button.matches('[data-clear-all]')) {
      button.closest('form')?.querySelectorAll<HTMLInputElement>('input[name="capability_code"]').forEach((input) => { input.checked = false; });
      return;
    }
    const capabilityAccountId = button.dataset.editCapabilities;
    if (capabilityAccountId) this.openCapabilities(capabilityAccountId);
    const statusAccountId = button.dataset.changeStatus;
    const nextStatus = button.dataset.nextStatus as 'active' | 'suspended' | undefined;
    if (statusAccountId && nextStatus) this.openStatus(statusAccountId, nextStatus);
  }

  private capabilityInputs(capabilities: OperationalCapability[], selected: Set<string>): string {
    return capabilities.map((capability) => `<label class="capability-option">
      <input name="capability_code" type="checkbox" value="${escapeHtml(capability.code)}" ${selected.has(capability.code) ? 'checked' : ''} />
      <span><strong>${escapeHtml(capability.name)}</strong><small>${escapeHtml(capability.code)}</small></span>
    </label>`).join('');
  }

  private openCreate(): void {
    if (!this.snapshot || !this.canManage()) return;
    const form = this.el<HTMLFormElement>('[data-create-form]');
    form.reset();
    this.el<HTMLElement>('[data-create-capabilities]').innerHTML = this.capabilityInputs(this.snapshot.capabilities, new Set());
    this.el<HTMLDialogElement>('[data-create-dialog]').showModal();
  }

  private openCapabilities(accountId: string): void {
    if (!this.snapshot || !this.canManage()) return;
    const account = this.account(accountId);
    const form = this.el<HTMLFormElement>('[data-capability-form]');
    form.reset();
    (form.elements.namedItem('account_id') as HTMLInputElement).value = account.account_id;
    this.el<HTMLElement>('[data-capability-account]').textContent = `${account.display_name} · ${account.email}`;
    this.el<HTMLElement>('[data-edit-capabilities]').innerHTML = this.capabilityInputs(
      this.snapshot.capabilities,
      new Set(account.capability_codes),
    );
    this.el<HTMLDialogElement>('[data-capability-dialog]').showModal();
  }

  private openStatus(accountId: string, status: 'active' | 'suspended'): void {
    if (!this.canManage()) return;
    const account = this.account(accountId);
    const form = this.el<HTMLFormElement>('[data-status-form]');
    form.reset();
    (form.elements.namedItem('account_id') as HTMLInputElement).value = account.account_id;
    (form.elements.namedItem('status') as HTMLInputElement).value = status;
    const verb = status === 'active' ? 'Reactivar' : 'Suspender';
    this.el<HTMLElement>('[data-status-title]').textContent = `${verb} cuenta`;
    this.el<HTMLElement>('[data-status-confirmation]').textContent = `${verb} el acceso operativo de ${account.display_name}.`;
    this.el<HTMLElement>('[data-status-submit]').textContent = verb;
    this.el<HTMLDialogElement>('[data-status-dialog]').showModal();
  }

  private async submitCreate(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const capabilityCodes = data.getAll('capability_code').map(String);
    if (!capabilityCodes.length) {
      this.toast('Selecciona al menos una capacidad.', 'error');
      return;
    }
    await this.mutate(form, async () => {
      await createOperationalAccess({
        email: String(data.get('email') ?? '').trim(),
        internalReference: String(data.get('internal_reference') ?? '').trim(),
        displayName: String(data.get('display_name') ?? '').trim(),
        capabilityCodes,
        cause: String(data.get('cause') ?? '').trim(),
      });
      this.el<HTMLDialogElement>('[data-create-dialog]').close();
    }, 'Acceso operativo creado.');
  }

  private async submitCapabilities(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const capabilityCodes = data.getAll('capability_code').map(String);
    if (!capabilityCodes.length) {
      this.toast('Selecciona al menos una capacidad.', 'error');
      return;
    }
    await this.mutate(form, async () => {
      await setOperationalAccessCapabilities({
        accountId: String(data.get('account_id') ?? ''),
        capabilityCodes,
        cause: String(data.get('cause') ?? '').trim(),
      });
      this.el<HTMLDialogElement>('[data-capability-dialog]').close();
    }, 'Capacidades actualizadas.');
  }

  private async submitStatus(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    await this.mutate(form, async () => {
      await setOperationalAccessStatus({
        accountId: String(data.get('account_id') ?? ''),
        status: String(data.get('status')) as 'active' | 'suspended',
        cause: String(data.get('cause') ?? '').trim(),
      });
      this.el<HTMLDialogElement>('[data-status-dialog]').close();
    }, 'Estado operativo actualizado.');
  }

  private account(accountId: string): OperationalAccess {
    const account = this.snapshot?.accounts.find((item) => item.account_id === accountId);
    if (!account) throw new Error('No se encontró la cuenta operativa.');
    return account;
  }

  private async mutate(form: HTMLFormElement, operation: () => Promise<void>, message: string): Promise<void> {
    this.busy(form, true);
    try {
      await operation();
      await this.reload();
      this.toast(message, 'success');
    } catch (error) {
      this.toast(this.message(error), 'error');
    } finally {
      this.busy(form, false);
    }
  }

  private busy(form: HTMLFormElement, value: boolean): void {
    form.querySelectorAll<HTMLInputElement | HTMLButtonElement | HTMLTextAreaElement>('input,button,textarea').forEach((element) => {
      element.disabled = value;
    });
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

document.querySelectorAll<HTMLElement>('[data-access-workspace]').forEach((root) => new AccessWorkspace(root));
