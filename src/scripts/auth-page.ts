import { currentSession, loginWithPassword, registerWithPassword } from '../services/auth';
import { mergeGuestCart } from '../services/cart';

const root = document.querySelector<HTMLElement>('[data-auth-app]');

if (root) {
  const login = root.querySelector<HTMLFormElement>('[data-login-form]')!;
  const register = root.querySelector<HTMLFormElement>('[data-register-form]')!;
  const message = root.querySelector<HTMLElement>('[data-auth-message]')!;

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
      window.location.href = '/cuenta';
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
        window.location.href = '/cuenta';
      } else {
        showMessage('Cuenta registrada. Revisa tu correo para confirmar el acceso antes de iniciar sesion.');
        busy(register, false);
      }
    } catch (error) {
      showMessage(error instanceof Error ? error.message : 'No se pudo crear la cuenta.', true);
      busy(register, false);
    }
  });

  void currentSession().then((session) => {
    if (session) window.location.href = '/cuenta';
  });
}
