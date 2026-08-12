import { supabase } from '../lib/supabase/client';
import { loadMySupportRequests, submitSupportRequest } from '../services/support';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');
}

class SupportWorkspace {
  private root: HTMLElement;

  constructor(root: HTMLElement) {
    this.root = root;
    this.form().addEventListener('submit', (event) => void this.submit(event));
    void this.initialize();
  }

  private form(): HTMLFormElement {
    return this.root.querySelector<HTMLFormElement>('[data-support-form]')!;
  }

  private async initialize(): Promise<void> {
    const { data } = await supabase.auth.getSession();
    if (!data.session) return;
    const email = this.form().elements.namedItem('email') as HTMLInputElement;
    email.value = data.session.user.email ?? '';
    try {
      const requests = await loadMySupportRequests();
      const section = this.root.querySelector<HTMLElement>('[data-my-support]')!;
      const list = this.root.querySelector<HTMLElement>('[data-my-support-list]')!;
      section.hidden = false;
      list.innerHTML = requests.length
        ? requests.map((item) => `<article class="support-request-row"><div><strong>${escapeHtml(item.subject)}</strong><span>${escapeHtml(String(item.status).replaceAll('_', ' '))}</span></div><time>${new Date(String(item.opened_at)).toLocaleDateString('es-MX')}</time></article>`).join('')
        : '<div class="state-box"><strong>Sin solicitudes</strong></div>';
    } catch {
      // A signed-in user without an active Personal Account has no private support history.
    }
  }

  private async submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = this.form();
    const data = new FormData(form);
    const button = form.querySelector<HTMLButtonElement>('button[type="submit"]')!;
    button.disabled = true;
    const message = this.root.querySelector<HTMLElement>('[data-support-message]')!;
    try {
      const params = new URLSearchParams(location.search);
      const result = await submitSupportRequest({
        subject: String(data.get('subject') ?? '').trim(),
        purpose: String(data.get('purpose') ?? '').trim(),
        body: String(data.get('body') ?? '').trim(),
        contactEmail: String(data.get('email') ?? '').trim(),
        contactPhone: String(data.get('phone') ?? '').trim(),
        isSensitive: data.get('sensitive') === 'on',
        referenceKind: params.get('tipo') ?? undefined,
        referenceId: params.get('id') ?? undefined,
      });
      form.reset();
      message.className = 'notice success wide';
      message.textContent = `Solicitud recibida. Referencia: ${result.reference ?? result.request_id}`;
      message.hidden = false;
      await this.initialize();
    } catch (error) {
      message.className = 'notice error wide';
      message.textContent = error instanceof Error ? error.message : 'No fue posible enviar la solicitud.';
      message.hidden = false;
    } finally {
      button.disabled = false;
    }
  }
}

document.querySelectorAll<HTMLElement>('[data-support-workspace]').forEach((root) => new SupportWorkspace(root));
