import {
  currentSession,
  ensurePersonalContext,
  googleLoginAvailable,
  loginWithGoogle,
  loginWithPassword,
  preferredNameForUser,
  registerWithPassword,
} from '../services/auth';
import { mergeGuestCart } from '../services/cart';

const root = document.querySelector<HTMLElement>('[data-auth-app]');

if (root) {
  const login = root.querySelector<HTMLFormElement>('[data-login-form]')!;
  const register = root.querySelector<HTMLFormElement>('[data-register-form]')!;
  const googleButton = root.querySelector<HTMLButtonElement>('[data-google-auth]')!;
  const googleButtonLabel = googleButton.querySelector<HTMLElement>('[data-google-auth-label]')!;
  const message = root.querySelector<HTMLElement>('[data-auth-message]')!;
  const searchParams = new URLSearchParams(window.location.search);
  let googleAvailable = false;

  function safeNextPath(value: string | null): string {
    if (!value?.startsWith('/') || value.startsWith('//')) return '/cuenta';
    const target = new URL(value, window.location.origin);
    if (target.origin !== window.location.origin || target.pathname === '/acceso') return '/cuenta';
    return `${target.pathname}${target.search}${target.hash}`;
  }

  const nextPath = safeNextPath(searchParams.get('next'));

  function showMessage(text: string, isError = false): void {
    message.textContent = text;
    message.className = `notice ${isError ? 'error' : 'success'}`;
    message.hidden = false;
  }

  function busy(form: HTMLFormElement, state: boolean): void {
    form.querySelectorAll<HTMLInputElement | HTMLButtonElement>('input, button').forEach((element) => {
      element.disabled = state;
    });
  }

  function oauthBusy(state: boolean): void {
    googleButton.disabled = state || !googleAvailable;
    googleButtonLabel.textContent = state ? 'Conectando con Google...' : 'Continuar con Google';
  }

  async function finishAuthentication(session: NonNullable<Awaited<ReturnType<typeof currentSession>>>): Promise<void> {
    await ensurePersonalContext(preferredNameForUser(session.user));
    const merge = await mergeGuestCart();
    if (merge?.rejected.length) {
      window.sessionStorage.setItem('cherry-mary:auth-notice', `${merge.rejected.length} articulo(s) ya no estaban disponibles.`);
    }
    window.location.replace(nextPath);
  }

  root.querySelectorAll<HTMLButtonElement>('[data-auth-tab]').forEach((tab) => {
    tab.addEventListener('click', () => {
      const mode = tab.dataset.authTab;
      root.querySelectorAll<HTMLButtonElement>('[data-auth-tab]').forEach((item) => {
        const active = item === tab;
        item.classList.toggle('active', active);
        item.setAttribute('aria-selected', String(active));
      });
      login.hidden = mode !== 'login';
      register.hidden = mode !== 'register';
      message.hidden = true;
    });
  });

  googleButton.addEventListener('click', async () => {
    oauthBusy(true);
    message.hidden = true;
    try {
      const callback = new URL('/acceso', window.location.origin);
      callback.searchParams.set('next', nextPath);
      await loginWithGoogle(callback.toString());
    } catch (error) {
      showMessage(error instanceof Error ? error.message : 'No se pudo continuar con Google.', true);
      oauthBusy(false);
    }
  });

  void googleLoginAvailable()
    .then((available) => {
      googleAvailable = available;
      googleButton.disabled = !available;
      if (!available) googleButton.title = 'Google estara disponible cuando se active el proveedor de acceso.';
    })
    .catch(() => {
      googleAvailable = true;
      googleButton.disabled = false;
    });

  login.addEventListener('submit', async (event) => {
    event.preventDefault();
    const formData = new FormData(login);
    busy(login, true);
    message.hidden = true;
    try {
      await loginWithPassword(String(formData.get('email') ?? '').trim(), String(formData.get('password') ?? ''));
      const merge = await mergeGuestCart();
      if (merge?.rejected.length) {
        window.sessionStorage.setItem('cherry-mary:auth-notice', `${merge.rejected.length} articulo(s) ya no estaban disponibles.`);
      }
      window.location.href = nextPath;
    } catch (error) {
      showMessage(error instanceof Error ? error.message : 'No se pudo iniciar sesion.', true);
      busy(login, false);
    }
  });

  register.addEventListener('submit', async (event) => {
    event.preventDefault();
    const formData = new FormData(register);
    const password = String(formData.get('password') ?? '');
    const confirmation = String(formData.get('password_confirmation') ?? '');
    if (password !== confirmation) {
      showMessage('Las contrasenas no coinciden.', true);
      return;
    }
    busy(register, true);
    message.hidden = true;
    try {
      const result = await registerWithPassword(
        String(formData.get('email') ?? '').trim(),
        password,
        String(formData.get('preferred_name') ?? '').trim(),
      );
      if (result.session) {
        await mergeGuestCart();
        window.location.href = nextPath;
      } else {
        showMessage('Cuenta registrada. Revisa tu correo para confirmar el acceso antes de iniciar sesion.');
        busy(register, false);
      }
    } catch (error) {
      showMessage(error instanceof Error ? error.message : 'No se pudo crear la cuenta.', true);
      busy(register, false);
    }
  });

  const oauthError = searchParams.get('error_description') ?? searchParams.get('error');
  if (oauthError) {
    showMessage(oauthError, true);
  } else {
    void currentSession()
      .then((session) => session && finishAuthentication(session))
      .catch((error) => {
        showMessage(error instanceof Error ? error.message : 'No se pudo completar el acceso.', true);
        oauthBusy(false);
      });
  }
}
