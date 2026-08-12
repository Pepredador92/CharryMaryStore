import { supabase } from '../lib/supabase/client';
import { ensurePersonalContext } from './auth';
import {
  clearGuestCart,
  readGuestCart,
  writeGuestCart,
  type CartItemKind,
  type GuestCartItem,
} from '../stores/guest-cart';

export type RemoteCartLine = {
  id: string;
  cart_id: string;
  line_kind: CartItemKind;
  presentation_id: string | null;
  package_id: string | null;
  quantity: number;
  validation_status: string;
};

export type RemoteCart = {
  id: string;
  status: string;
  expires_at: string;
  lines: RemoteCartLine[];
};

export type MergeResult = {
  operation_id: string;
  cart_id: string;
  accepted: Array<{ line_kind: CartItemKind; target_id: string; quantity: number }>;
  rejected: Array<{ line_kind: CartItemKind; target_id: string; quantity: number; reason: string }>;
};

export async function loadRemoteCart(): Promise<RemoteCart> {
  await ensurePersonalContext();
  const { data: cartId, error: cartError } = await supabase.rpc('get_or_create_current_cart');
  if (cartError || !cartId) throw cartError ?? new Error('No se pudo abrir el carrito.');

  const [cartResult, linesResult] = await Promise.all([
    supabase.from('carts').select('*').eq('id', cartId).single(),
    supabase.from('cart_lines').select('*').eq('cart_id', cartId).order('created_at'),
  ]);
  if (cartResult.error) throw cartResult.error;
  if (linesResult.error) throw linesResult.error;
  return { ...cartResult.data, lines: (linesResult.data ?? []) as RemoteCartLine[] } as RemoteCart;
}

export async function setRemoteCartItem(
  kind: CartItemKind,
  targetId: string,
  quantity: number,
  mode: 'set' | 'add' = 'set',
): Promise<void> {
  const { error } = await supabase.rpc('set_authenticated_cart_item', {
    p_line_kind: kind,
    p_target_id: targetId,
    p_quantity: quantity,
    p_mode: mode,
  });
  if (error) throw error;
  window.dispatchEvent(new CustomEvent('cherry-mary:remote-cart-change'));
}

export async function mergeGuestCart(): Promise<MergeResult | null> {
  const guest = readGuestCart();
  if (!guest.items.length) return null;

  await ensurePersonalContext();
  const { data, error } = await supabase.rpc('merge_guest_cart', {
    p_operation_id: guest.mergeOperationId,
    p_items: guest.items.map((item) => ({
      line_kind: item.kind,
      target_id: item.targetId,
      quantity: item.quantity,
    })),
  });
  if (error) throw error;

  const result = data as MergeResult;
  const rejectedKeys = new Set(result.rejected.map((item) => `${item.line_kind}:${item.target_id}`));
  const rejectedItems: GuestCartItem[] = guest.items.filter((item) => rejectedKeys.has(`${item.kind}:${item.targetId}`));
  if (rejectedItems.length) writeGuestCart(rejectedItems);
  else clearGuestCart();
  window.dispatchEvent(new CustomEvent('cherry-mary:remote-cart-change'));
  return result;
}
