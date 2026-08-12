import {
  currentSession,
  ensurePersonalContext,
  logout,
  onSessionChange,
  operationalCapabilities,
  preferredNameForUser,
} from '../services/auth';
import { loadRemoteCart, mergeGuestCart } from '../services/cart';
import { guestCartCount, subscribeGuestCart } from '../stores/guest-cart';

const count = document.querySelector<HTMLElement>('[data-cart-count]');
const accountLink = document.querySelector<HTMLAnchorElement>('[data-account-link]');
const adminLink = document.querySelector<HTMLAnchorElement>('[data-admin-link]');
const signOutButton = document.querySelector<HTMLButtonElement>('[data-store-sign-out]');
const notice = document.querySelector<HTMLElement>('[data-shell-notice]');

function showNotice(message: string): void {
  if (!notice) return;
  notice.textContent = message;
  notice.hidden = false;
}

async function refreshShell(session?: Awaited<ReturnType<typeof currentSession>>): Promise<void> {
  const activeSession = session === undefined ? await currentSession() : session;
  if (!activeSession) {
    if (accountLink) accountLink.textContent = 'Iniciar sesion';
    if (signOutButton) signOutButton.hidden = true;
    if (adminLink) adminLink.hidden = true;
    if (count) count.textContent = String(guestCartCount());
    return;
  }

  if (accountLink) accountLink.textContent = 'Mi cuenta';
  if (signOutButton) signOutButton.hidden = false;
  try {
    await ensurePersonalContext(preferredNameForUser(activeSession.user));
    const merge = await mergeGuestCart();
    if (merge?.rejected.length) {
      showNotice(`${merge.rejected.length} articulo(s) ya no estaban disponibles y permanecen en el carrito local.`);
    }
    const [cart, capabilities] = await Promise.all([loadRemoteCart(), operationalCapabilities()]);
    if (count) count.textContent = String(cart.lines.reduce((total, line) => total + line.quantity, 0));
    if (adminLink) adminLink.hidden = capabilities.size === 0;
  } catch (error) {
    showNotice(error instanceof Error ? error.message : 'No se pudo sincronizar la sesion.');
  }
}

signOutButton?.addEventListener('click', async () => {
  signOutButton.disabled = true;
  try {
    await logout();
    window.location.href = '/';
  } catch (error) {
    showNotice(error instanceof Error ? error.message : 'No se pudo cerrar la sesion.');
    signOutButton.disabled = false;
  }
});

subscribeGuestCart(() => void refreshShell());
window.addEventListener('cherry-mary:remote-cart-change', () => void refreshShell());
onSessionChange((session) => window.setTimeout(() => void refreshShell(session), 0));
void refreshShell();
