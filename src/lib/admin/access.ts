import { supabase } from '../supabase/client';

export type OperationalCapability = {
  id: string;
  code: string;
  name: string;
  description: string | null;
};

export type OperationalAccess = {
  account_id: string;
  person_id: string;
  internal_reference: string;
  display_name: string;
  email: string;
  person_status: 'active' | 'suspended' | 'ended';
  account_status: 'invited' | 'active' | 'suspended' | 'revoked';
  activated_at: string | null;
  revoked_at: string | null;
  created_at: string;
  is_current: boolean;
  capability_codes: string[];
};

export type OperationalAccessSnapshot = {
  current_account_id: string;
  capabilities: OperationalCapability[];
  accounts: OperationalAccess[];
};

function unwrap<T>(
  result: { data: T | null; error: { message: string } | null },
  context: string,
): T {
  if (result.error) throw new Error(`${context}: ${result.error.message}`);
  return result.data as T;
}

export async function loadOperationalAccess(): Promise<OperationalAccessSnapshot> {
  return unwrap(
    await supabase.rpc('operational_access_snapshot'),
    'No se pudieron cargar los accesos operativos',
  );
}

export async function createOperationalAccess(input: {
  email: string;
  internalReference: string;
  displayName: string;
  capabilityCodes: string[];
  cause: string;
}): Promise<string> {
  return unwrap(
    await supabase.rpc('create_operational_access', {
      p_email: input.email,
      p_internal_reference: input.internalReference,
      p_display_name: input.displayName,
      p_capability_codes: input.capabilityCodes,
      p_cause: input.cause,
    }),
    'No se pudo crear el acceso operativo',
  );
}

export async function setOperationalAccessCapabilities(input: {
  accountId: string;
  capabilityCodes: string[];
  cause: string;
}): Promise<void> {
  unwrap(
    await supabase.rpc('set_operational_access_capabilities', {
      p_account_id: input.accountId,
      p_capability_codes: input.capabilityCodes,
      p_cause: input.cause,
    }),
    'No se pudieron actualizar las capacidades',
  );
}

export async function setOperationalAccessStatus(input: {
  accountId: string;
  status: 'active' | 'suspended';
  cause: string;
}): Promise<void> {
  unwrap(
    await supabase.rpc('set_operational_access_status', {
      p_account_id: input.accountId,
      p_status: input.status,
      p_cause: input.cause,
    }),
    'No se pudo actualizar el estado operativo',
  );
}
