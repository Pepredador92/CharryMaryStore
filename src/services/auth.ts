import type { Session, User } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase/client';

export type PersonalContext = {
  personal_account_id: string;
  customer_id: string;
  preferred_name: string | null;
  contact_email: string | null;
  contact_phone: string | null;
  account_status: string;
};

function firstRow<T>(data: T[] | null, message: string): T {
  const row = data?.[0];
  if (!row) throw new Error(message);
  return row;
}

export async function currentSession(): Promise<Session | null> {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  return data.session;
}

export function preferredNameForUser(user: User): string {
  const metadata = user.user_metadata as Record<string, unknown>;
  const candidate = metadata.preferred_name ?? metadata.full_name ?? metadata.name;
  return typeof candidate === 'string' ? candidate.trim() : '';
}

export async function registerWithPassword(
  email: string,
  password: string,
  preferredName: string,
): Promise<{ session: Session | null; user: User | null }> {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { preferred_name: preferredName.trim() || null } },
  });
  if (error) throw error;
  if (data.session) await ensurePersonalContext(preferredName);
  return data;
}

export async function loginWithPassword(email: string, password: string): Promise<Session> {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error || !data.session) throw error ?? new Error('No se pudo iniciar sesion.');
  await ensurePersonalContext(preferredNameForUser(data.user));
  return data.session;
}

export async function loginWithGoogle(redirectTo: string): Promise<void> {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo },
  });
  if (error) throw error;
}

export async function googleLoginAvailable(): Promise<boolean> {
  const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
  const supabaseKey = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;
  const response = await fetch(`${supabaseUrl}/auth/v1/settings`, {
    headers: { apikey: supabaseKey },
    cache: 'no-store',
  });
  if (!response.ok) throw new Error('No se pudo consultar la disponibilidad de Google.');
  const settings = (await response.json()) as { external?: { google?: boolean } };
  return settings.external?.google === true;
}

export async function logout(): Promise<void> {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function ensurePersonalContext(preferredName = '', contactPhone = ''): Promise<PersonalContext> {
  const { data, error } = await supabase.rpc('ensure_personal_account', {
    p_preferred_name: preferredName.trim() || null,
    p_contact_phone: contactPhone.trim() || null,
  });
  if (error) throw error;
  return firstRow(data as PersonalContext[] | null, 'No se pudo inicializar la Cuenta personal.');
}

export async function operationalCapabilities(): Promise<Set<string>> {
  const { data, error } = await supabase.rpc('current_operational_capabilities');
  if (error) throw error;
  return new Set(((data ?? []) as Array<{ code: string }>).map((item) => item.code));
}

export function onSessionChange(listener: (session: Session | null) => void): () => void {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => listener(session));
  return () => data.subscription.unsubscribe();
}
