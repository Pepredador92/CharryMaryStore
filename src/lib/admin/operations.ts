import { supabase } from '../../lib/supabase/client';

export type JsonRecord = Record<string, any>;

function unwrap<T>(result: { data: T | null; error: { message: string } | null }, context: string): T {
  if (result.error) throw new Error(`${context}: ${result.error.message}`);
  return result.data as T;
}

export async function loadOperationalDashboard(): Promise<JsonRecord> {
  return unwrap(await supabase.rpc('admin_dashboard'), 'No se pudo cargar el dashboard');
}

export async function loadOrders(): Promise<JsonRecord[]> {
  return unwrap(
    await supabase.from('orders').select('*').order('placed_at', { ascending: false }).limit(500),
    'No se pudieron cargar los pedidos',
  ) ?? [];
}

export async function loadOrderDetail(id: string): Promise<JsonRecord> {
  return unwrap(await supabase.rpc('admin_order_detail', { p_order_id: id }), 'No se pudo cargar el pedido');
}

export async function manageOrder(id: string, action: 'confirm' | 'cancel', cause?: string): Promise<void> {
  unwrap(await supabase.rpc('manage_order', { p_order_id: id, p_action: action, p_cause: cause ?? null }), 'No se pudo actualizar el pedido');
}

export async function authorizePreparation(orderId: string): Promise<JsonRecord> {
  return unwrap(await supabase.rpc('authorize_order_preparation', { p_order_id: orderId }), 'No se pudo autorizar la preparación');
}

export async function loadPreparations(): Promise<JsonRecord[]> {
  return unwrap(
    await supabase.from('preparations').select('*, orders(order_number, commercial_status)').order('created_at', { ascending: false }).limit(500),
    'No se pudieron cargar las preparaciones',
  ) ?? [];
}

export async function loadPreparationDetail(id: string): Promise<JsonRecord> {
  return unwrap(await supabase.rpc('admin_preparation_detail', { p_preparation_id: id }), 'No se pudo cargar la preparación');
}

export async function managePreparation(
  id: string,
  action: string,
  orderItemId?: string,
  cause?: string,
): Promise<void> {
  unwrap(
    await supabase.rpc('manage_preparation', {
      p_preparation_id: id,
      p_action: action,
      p_order_item_id: orderItemId ?? null,
      p_cause: cause ?? null,
    }),
    'No se pudo actualizar la preparación',
  );
}

export async function createDelivery(orderId: string): Promise<JsonRecord> {
  return unwrap(await supabase.rpc('create_order_delivery', { p_order_id: orderId }), 'No se pudo crear la entrega');
}

export async function loadDeliveries(): Promise<JsonRecord[]> {
  return unwrap(
    await supabase.from('deliveries').select('*, orders(order_number, commercial_status)').order('recognized_at', { ascending: false }).limit(500),
    'No se pudieron cargar las entregas',
  ) ?? [];
}

export async function loadDeliveryDetail(id: string): Promise<JsonRecord> {
  return unwrap(await supabase.rpc('admin_delivery_detail', { p_delivery_id: id }), 'No se pudo cargar la entrega');
}

export async function loadDeliveryAssignmentOptions(): Promise<JsonRecord> {
  return unwrap(await supabase.rpc('delivery_assignment_options'), 'No se pudieron cargar responsables y proveedores');
}

export async function saveLogisticsProvider(input: {
  id?: string;
  name: string;
  externalReference?: string;
  isActive?: boolean;
}): Promise<string> {
  return unwrap(
    await supabase.rpc('save_logistics_provider', {
      p_provider_id: input.id ?? null,
      p_name: input.name,
      p_external_reference: input.externalReference ?? null,
      p_is_active: input.isActive ?? true,
    }),
    'No se pudo guardar el proveedor',
  );
}

export async function assignDelivery(input: {
  deliveryId: string;
  operationalPersonId?: string;
  providerId?: string;
  externalPersonReference?: string;
  cause: string;
}): Promise<void> {
  unwrap(
    await supabase.rpc('assign_delivery', {
      p_delivery_id: input.deliveryId,
      p_operational_person_id: input.operationalPersonId ?? null,
      p_logistics_provider_id: input.providerId ?? null,
      p_external_person_reference: input.externalPersonReference ?? null,
      p_assignment_kind: 'responsible',
      p_cause: input.cause,
    }),
    'No se pudo asignar la entrega',
  );
}

export async function recordDeliveryCustody(input: {
  deliveryId: string;
  eventKind: string;
  fromPartyKind: string;
  fromOperationalPersonId?: string;
  fromProviderId?: string;
  toPartyKind: string;
  toOperationalPersonId?: string;
  toProviderId?: string;
  externalPartyReference?: string;
  cause?: string;
}): Promise<void> {
  unwrap(
    await supabase.rpc('record_delivery_custody', {
      p_delivery_id: input.deliveryId,
      p_event_kind: input.eventKind,
      p_from_party_kind: input.fromPartyKind,
      p_from_operational_person_id: input.fromOperationalPersonId ?? null,
      p_from_provider_id: input.fromProviderId ?? null,
      p_to_party_kind: input.toPartyKind,
      p_to_operational_person_id: input.toOperationalPersonId ?? null,
      p_to_provider_id: input.toProviderId ?? null,
      p_external_party_reference: input.externalPartyReference ?? null,
      p_cause: input.cause ?? null,
    }),
    'No se pudo registrar la custodia',
  );
}

export async function setDeliveryState(id: string, action: string, cause: string): Promise<void> {
  unwrap(await supabase.rpc('set_delivery_state', { p_delivery_id: id, p_action: action, p_cause: cause }), 'No se pudo actualizar la entrega');
}

export async function registerDeliveryAttempt(input: {
  deliveryId: string;
  result: string;
  failureCause?: string;
  receiptConfirmation?: string;
  startedAt?: string;
}): Promise<void> {
  unwrap(
    await supabase.rpc('register_delivery_attempt', {
      p_delivery_id: input.deliveryId,
      p_result: input.result,
      p_failure_cause: input.failureCause ?? null,
      p_receipt_confirmation: input.receiptConfirmation ?? null,
      p_event_source: 'admin_web',
      p_started_at: input.startedAt || null,
    }),
    'No se pudo registrar el intento',
  );
}

export async function loadDeliveryEvidence(deliveryId: string): Promise<JsonRecord[]> {
  return unwrap(await supabase.rpc('list_delivery_evidence', { p_delivery_id: deliveryId }), 'No se pudo cargar la evidencia') ?? [];
}

export async function registerDeliveryEvidence(input: JsonRecord): Promise<void> {
  unwrap(
    await supabase.rpc('register_delivery_evidence', {
      p_delivery_id: input.deliveryId,
      p_delivery_attempt_id: input.attemptId || null,
      p_purpose: input.purpose,
      p_evidence_kind: input.evidenceKind,
      p_retention_class: input.retentionClass,
      p_dispute_context: input.disputeContext || null,
      p_exceptional_obligation_reference: input.obligationReference || null,
      p_content_reference: input.contentReference || null,
      p_content_mime_type: input.contentMimeType || null,
      p_is_sensitive: Boolean(input.isSensitive),
      p_retention_due_at: input.retentionDueAt,
      p_review_at: input.reviewAt || null,
    }),
    'No se pudo registrar la evidencia',
  );
}

export async function deleteDeliveryEvidence(id: string, reason: string): Promise<void> {
  unwrap(await supabase.rpc('delete_delivery_evidence', { p_evidence_id: id, p_reason: reason }), 'No se pudo registrar la eliminación');
}

export async function loadSupportRequests(id?: string): Promise<JsonRecord | JsonRecord[]> {
  return unwrap(await supabase.rpc('support_requests_view', { p_request_id: id ?? null }), 'No se pudo cargar atención');
}

export async function respondSupport(id: string, body: string, isSensitive: boolean): Promise<void> {
  unwrap(await supabase.rpc('respond_support_request', { p_request_id: id, p_body: body, p_is_sensitive: isSensitive }), 'No se pudo registrar la respuesta');
}

export async function setSupportStatus(input: {
  id: string;
  status: string;
  cause?: string;
  referenceKind?: string;
  referenceId?: string;
}): Promise<void> {
  unwrap(
    await supabase.rpc('set_support_request_status', {
      p_request_id: input.id,
      p_status: input.status,
      p_cause: input.cause ?? null,
      p_reference_kind: input.referenceKind || null,
      p_reference_id: input.referenceId || null,
    }),
    'No se pudo actualizar la solicitud',
  );
}

export async function loadAuditEvents(): Promise<JsonRecord[]> {
  return unwrap(
    await supabase.from('audit_events').select('*').order('occurred_at', { ascending: false }).limit(500),
    'No se pudo cargar la auditoría',
  ) ?? [];
}
