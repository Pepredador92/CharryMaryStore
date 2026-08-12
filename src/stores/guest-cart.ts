export type CartItemKind = 'presentation' | 'package';

export type GuestCartItem = {
  kind: CartItemKind;
  targetId: string;
  quantity: number;
};

export type GuestCartState = {
  version: 1;
  updatedAt: string;
  mergeOperationId: string;
  items: GuestCartItem[];
};

const STORAGE_KEY = 'cherry-mary:guest-cart:v1';
const CART_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;
const EVENT_NAME = 'cherry-mary:cart-change';

function emptyCart(): GuestCartState {
  return {
    version: 1,
    updatedAt: new Date().toISOString(),
    mergeOperationId: crypto.randomUUID(),
    items: [],
  };
}

function validItem(value: unknown): value is GuestCartItem {
  if (!value || typeof value !== 'object') return false;
  const item = value as Partial<GuestCartItem>;
  return (
    (item.kind === 'presentation' || item.kind === 'package') &&
    typeof item.targetId === 'string' &&
    item.targetId.length > 0 &&
    Number.isInteger(item.quantity) &&
    Number(item.quantity) > 0 &&
    Number(item.quantity) <= 99
  );
}

export function readGuestCart(): GuestCartState {
  const raw = window.localStorage.getItem(STORAGE_KEY);
  if (!raw) return emptyCart();

  try {
    const parsed = JSON.parse(raw) as Partial<GuestCartState>;
    const updatedAt = new Date(parsed.updatedAt ?? '').getTime();
    if (!Number.isFinite(updatedAt) || Date.now() - updatedAt >= CART_LIFETIME_MS) {
      window.localStorage.removeItem(STORAGE_KEY);
      return emptyCart();
    }
    return {
      version: 1,
      updatedAt: new Date(updatedAt).toISOString(),
      mergeOperationId: typeof parsed.mergeOperationId === 'string' ? parsed.mergeOperationId : crypto.randomUUID(),
      items: Array.isArray(parsed.items) ? parsed.items.filter(validItem) : [],
    };
  } catch {
    window.localStorage.removeItem(STORAGE_KEY);
    return emptyCart();
  }
}

export function writeGuestCart(items: GuestCartItem[], mergeOperationId?: string): GuestCartState {
  const state: GuestCartState = {
    version: 1,
    updatedAt: new Date().toISOString(),
    mergeOperationId: mergeOperationId ?? crypto.randomUUID(),
    items: items.filter(validItem),
  };
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  window.dispatchEvent(new CustomEvent(EVENT_NAME, { detail: state }));
  return state;
}

export function setGuestCartItem(kind: CartItemKind, targetId: string, quantity: number): GuestCartState {
  const current = readGuestCart();
  const items = current.items.filter((item) => !(item.kind === kind && item.targetId === targetId));
  if (quantity > 0) items.push({ kind, targetId, quantity: Math.min(99, Math.trunc(quantity)) });
  return writeGuestCart(items, current.mergeOperationId);
}

export function addGuestCartItem(kind: CartItemKind, targetId: string, quantity = 1): GuestCartState {
  const current = readGuestCart();
  const existing = current.items.find((item) => item.kind === kind && item.targetId === targetId);
  return setGuestCartItem(kind, targetId, Math.min(99, (existing?.quantity ?? 0) + quantity));
}

export function clearGuestCart(): void {
  window.localStorage.removeItem(STORAGE_KEY);
  window.dispatchEvent(new CustomEvent(EVENT_NAME, { detail: emptyCart() }));
}

export function guestCartCount(): number {
  return readGuestCart().items.reduce((total, item) => total + item.quantity, 0);
}

export function subscribeGuestCart(listener: (state: GuestCartState) => void): () => void {
  const handler = (event: Event) => listener((event as CustomEvent<GuestCartState>).detail ?? readGuestCart());
  window.addEventListener(EVENT_NAME, handler);
  window.addEventListener('storage', handler);
  return () => {
    window.removeEventListener(EVENT_NAME, handler);
    window.removeEventListener('storage', handler);
  };
}
