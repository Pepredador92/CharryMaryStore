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

export type SupportConversationSummary = {
  id: string;
  subject: string;
  purpose: string;
  status: string;
  opened_at: string;
  last_message_at: string | null;
  last_message_preview: string | null;
  unread_count: number;
};

export type SupportMessage = {
  id: string;
  direction: 'incoming' | 'outgoing';
  author_kind: 'visitor' | 'customer' | 'operational_person' | 'system_notification';
  body: string;
  is_sensitive: boolean;
  sent_at: string;
};

export type SupportConversation = {
  request: SupportConversationSummary;
  messages: SupportMessage[];
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

export async function loadMySupportRequests(): Promise<SupportConversationSummary[]> {
  const { data, error } = await supabase.rpc('customer_support_conversations', { p_request_id: null });
  if (error) throw error;
  return (data ?? []) as SupportConversationSummary[];
}

export async function loadSupportConversation(id: string): Promise<SupportConversation> {
  const { data, error } = await supabase.rpc('customer_support_conversations', { p_request_id: id });
  if (error) throw error;
  return data as SupportConversation;
}

export async function sendSupportMessage(id: string, body: string): Promise<void> {
  const { error } = await supabase.rpc('customer_send_support_message', {
    p_request_id: id,
    p_body: body,
  });
  if (error) throw error;
}

export async function loadSupportUnreadCount(): Promise<number> {
  const { data, error } = await supabase.rpc('customer_support_unread_count');
  if (error) throw error;
  return Number(data ?? 0);
}
