import { supabase } from '../lib/supabase/client';
import {
  loadMySupportRequests,
  loadSupportConversation,
  sendSupportMessage,
  submitSupportRequest,
  type SupportConversation,
  type SupportConversationSummary,
} from '../services/support';

const dateFormatter = new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium', timeStyle: 'short' });

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function statusLabel(value: string): string {
  const labels: Record<string, string> = {
    open: 'Recibido',
    in_attention: 'En conversación',
    resolved: 'Resuelto',
    channelled: 'En seguimiento',
    closed: 'Cerrado',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

class SupportWorkspace {
  private root: HTMLElement;
  private conversations: SupportConversationSummary[] = [];
  private selectedId: string | null = null;

  constructor(root: HTMLElement) {
    this.root = root;
    this.root.querySelectorAll<HTMLFormElement>('[data-support-form]').forEach((form) => {
      form.addEventListener('submit', (event) => void this.submitNewConversation(event));
    });
    this.root.querySelector<HTMLFormElement>('[data-chat-reply]')?.addEventListener('submit', (event) => void this.reply(event));
    this.root.addEventListener('click', (event) => void this.click(event));
    void this.initialize();
  }

  private async initialize(): Promise<void> {
    const { data } = await supabase.auth.getSession();
    if (!data.session) return;

    this.root.querySelector<HTMLElement>('[data-support-public]')!.hidden = true;
    this.root.querySelector<HTMLElement>('[data-support-auth]')!.hidden = false;

    try {
      await this.refreshConversations();
      const requestedId = new URLSearchParams(location.search).get('chat');
      const initialId = requestedId && this.conversations.some((item) => item.id === requestedId)
        ? requestedId
        : this.conversations[0]?.id;
      if (initialId) await this.openConversation(initialId);
      window.setInterval(() => void this.poll(), 12000);
    } catch (error) {
      this.showError(error instanceof Error ? error.message : 'No se pudieron cargar tus conversaciones.');
    }
  }

  private async poll(): Promise<void> {
    if (document.hidden) return;
    try {
      if (this.selectedId) await this.loadSelected(false);
      await this.refreshConversations();
      window.dispatchEvent(new CustomEvent('cherry-mary:support-change'));
    } catch {
      // Keep the current conversation visible during a transient connection failure.
    }
  }

  private async refreshConversations(): Promise<void> {
    this.conversations = await loadMySupportRequests();
    const list = this.root.querySelector<HTMLElement>('[data-my-support-list]')!;
    list.innerHTML = this.conversations.length
      ? this.conversations.map((item) => `<button class="support-conversation-row${item.id === this.selectedId ? ' active' : ''}" type="button" data-chat-id="${item.id}">
          <span class="support-conversation-avatar">M</span>
          <span class="support-conversation-copy"><span><strong>${escapeHtml(item.subject)}</strong><time>${dateFormatter.format(new Date(item.last_message_at ?? item.opened_at))}</time></span><small>${escapeHtml(item.last_message_preview ?? item.purpose)}</small></span>
          ${Number(item.unread_count) > 0 ? `<span class="support-unread-badge">${Math.min(Number(item.unread_count), 99)}</span>` : ''}
        </button>`).join('')
      : '<div class="support-inbox-empty">Todavía no hay conversaciones.</div>';
  }

  private async openConversation(id: string): Promise<void> {
    this.selectedId = id;
    history.replaceState({}, '', `/ayuda?chat=${encodeURIComponent(id)}`);
    await this.loadSelected(true);
    await this.refreshConversations();
    window.dispatchEvent(new CustomEvent('cherry-mary:support-change'));
  }

  private async loadSelected(scroll: boolean): Promise<void> {
    if (!this.selectedId) return;
    const conversation = await loadSupportConversation(this.selectedId);
    this.renderConversation(conversation, scroll);
  }

  private renderConversation(conversation: SupportConversation, scroll: boolean): void {
    const header = this.root.querySelector<HTMLElement>('[data-thread-header]')!;
    const empty = this.root.querySelector<HTMLElement>('[data-thread-empty]')!;
    const messages = this.root.querySelector<HTMLElement>('[data-chat-messages]')!;
    const composer = this.root.querySelector<HTMLFormElement>('[data-chat-reply]')!;
    const closed = this.root.querySelector<HTMLElement>('[data-thread-closed]')!;

    const keepAtBottom = scroll || messages.scrollHeight - messages.scrollTop - messages.clientHeight < 80;
    empty.hidden = true;
    header.hidden = false;
    messages.hidden = false;
    header.innerHTML = `<span class="support-conversation-avatar">M</span><div><strong>Mary</strong><span>${escapeHtml(conversation.request.subject)} · ${escapeHtml(statusLabel(conversation.request.status))}</span></div>`;
    messages.innerHTML = conversation.messages.map((message) => {
      const own = message.direction === 'incoming' && (message.author_kind === 'customer' || message.author_kind === 'visitor');
      return `<article class="customer-chat-message ${own ? 'own' : 'mary'}"><header><strong>${own ? 'Tú' : 'Mary'}</strong><time>${dateFormatter.format(new Date(message.sent_at))}</time></header><p>${escapeHtml(message.body)}</p></article>`;
    }).join('');

    const isClosed = conversation.request.status === 'closed';
    composer.hidden = isClosed;
    closed.hidden = !isClosed;
    if (keepAtBottom) requestAnimationFrame(() => { messages.scrollTop = messages.scrollHeight; });
  }

  private async click(event: MouseEvent): Promise<void> {
    const target = event.target as Element;
    const conversationButton = target.closest<HTMLElement>('[data-chat-id]');
    if (conversationButton?.dataset.chatId) {
      await this.openConversation(conversationButton.dataset.chatId);
      return;
    }
    if (target.closest('[data-new-chat]')) this.root.querySelector<HTMLDialogElement>('[data-new-chat-dialog]')!.showModal();
    if (target.closest('[data-close-new-chat]')) this.root.querySelector<HTMLDialogElement>('[data-new-chat-dialog]')!.close();
  }

  private async submitNewConversation(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const button = form.querySelector<HTMLButtonElement>('button[type="submit"]')!;
    const message = form.querySelector<HTMLElement>('[data-support-message]')!;
    const body = String(data.get('body') ?? '').trim();
    button.disabled = true;
    try {
      const params = new URLSearchParams(location.search);
      const result = await submitSupportRequest({
        subject: String(data.get('subject') ?? '').trim(),
        purpose: body.slice(0, 500),
        body,
        contactEmail: String(data.get('email') ?? '').trim(),
        contactPhone: String(data.get('phone') ?? '').trim(),
        isSensitive: data.get('sensitive') === 'on',
        referenceKind: params.get('tipo') ?? undefined,
        referenceId: params.get('id') ?? undefined,
      });
      form.reset();
      if (form.dataset.supportMode === 'account') {
        this.root.querySelector<HTMLDialogElement>('[data-new-chat-dialog]')!.close();
        await this.refreshConversations();
        if (result.request_id) await this.openConversation(result.request_id);
      } else {
        message.className = 'notice success wide';
        message.textContent = `Mensaje recibido. Tu referencia es ${result.reference ?? result.request_id}.`;
        message.hidden = false;
      }
    } catch (error) {
      message.className = 'notice error wide';
      message.textContent = error instanceof Error ? error.message : 'No fue posible enviar el mensaje.';
      message.hidden = false;
    } finally {
      button.disabled = false;
    }
  }

  private async reply(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!this.selectedId) return;
    const form = event.currentTarget as HTMLFormElement;
    const field = form.elements.namedItem('body') as HTMLTextAreaElement;
    const body = field.value.trim();
    if (!body) return;
    const button = form.querySelector<HTMLButtonElement>('button[type="submit"]')!;
    button.disabled = true;
    try {
      await sendSupportMessage(this.selectedId, body);
      field.value = '';
      await this.loadSelected(true);
      await this.refreshConversations();
    } catch (error) {
      this.showError(error instanceof Error ? error.message : 'No fue posible enviar el mensaje.');
    } finally {
      button.disabled = false;
    }
  }

  private showError(message: string): void {
    const target = this.root.querySelector<HTMLElement>('[data-support-error]')!;
    target.textContent = message;
    target.className = 'notice error';
    target.hidden = false;
  }
}

document.querySelectorAll<HTMLElement>('[data-support-workspace]').forEach((root) => new SupportWorkspace(root));
