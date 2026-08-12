import { supabase } from '../lib/supabase/client';

export type SupportRequestInput = {
  subject: string;
  purpose: string;
  body: string;
  contactEmail?: string;
  contactPhone?: string;
  isSensitive: boolean;
  referenceKind?: string;
  referenceId?: string;
};

export async function submitSupportRequest(input: SupportRequestInput): Promise<Record<string, string | null>> {
  const { data, error } = await supabase.rpc('submit_support_request', {
    p_subject: input.subject,
    p_purpose: input.purpose,
    p_body: input.body,
    p_contact_email: input.contactEmail || null,
    p_contact_phone: input.contactPhone || null,
    p_is_sensitive: input.isSensitive,
    p_reference_kind: input.referenceKind || null,
    p_reference_id: input.referenceId || null,
  });
  if (error) throw error;
  return data as Record<string, string | null>;
}

export async function loadMySupportRequests(): Promise<Record<string, unknown>[]> {
  const { data, error } = await supabase.rpc('support_requests_view', { p_request_id: null });
  if (error) throw error;
  return (data ?? []) as Record<string, unknown>[];
}
