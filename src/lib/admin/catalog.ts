import { supabase } from '../supabase/client';

export const CATALOG_BUCKET = 'catalog-resources';

export type Product = {
  id: string;
  name: string;
  description: string | null;
  usage_instructions: string | null;
  warnings: string | null;
  is_active: boolean;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
};

export type Presentation = {
  id: string;
  product_id: string;
  sku: string;
  variant_label: string | null;
  attributes: Record<string, unknown> | null;
  current_price_amount_minor: number;
  currency_code: string;
  is_active: boolean;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PresentationInventory = {
  presentation_id: string;
  on_hand_quantity: number;
  updated_at: string;
};

export type InventoryMovement = {
  id: string;
  presentation_id: string;
  quantity_delta: number;
  movement_kind: string;
  cause: string;
  occurred_at: string;
  actor_operational_person_id: string | null;
};

export type Package = {
  id: string;
  name: string;
  description: string | null;
  current_price_amount_minor: number;
  currency_code: string;
  is_active: boolean;
  valid_from: string | null;
  valid_until: string | null;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PackageComponent = {
  id: string;
  package_id: string;
  presentation_id: string;
  quantity: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type Classification = {
  id: string;
  name: string;
  description: string | null;
  parent_id: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type ClassificationAssignment = {
  id: string;
  classification_id: string;
  product_id: string | null;
  package_id: string | null;
  created_at: string;
};

export type CatalogResource = {
  id: string;
  product_id: string | null;
  presentation_id: string | null;
  package_id: string | null;
  resource_kind: string;
  source_reference: string;
  alt_text: string | null;
  sort_order: number;
  is_primary: boolean;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type CatalogSnapshot = {
  products: Product[];
  presentations: Presentation[];
  inventory: PresentationInventory[];
  movements: InventoryMovement[];
  packages: Package[];
  components: PackageComponent[];
  classifications: Classification[];
  assignments: ClassificationAssignment[];
  resources: CatalogResource[];
};

type QueryResult<T> = { data: T | null; error: { message: string } | null };

function requireData<T>(result: QueryResult<T>, context: string): T {
  if (result.error) {
    throw new Error(`${context}: ${result.error.message}`);
  }
  return result.data ?? ([] as T);
}

export async function getCurrentCapabilities(): Promise<Set<string>> {
  const result = await supabase.rpc('current_operational_capabilities');
  const rows = requireData<Array<{ code: string }>>(result, 'No se pudieron consultar las capacidades');
  return new Set(rows.map(({ code }) => code));
}

export async function loadCatalogSnapshot(): Promise<CatalogSnapshot> {
  const [products, presentations, inventory, movements, packages, components, classifications, assignments, resources] =
    await Promise.all([
      supabase.from('products').select('*').order('name'),
      supabase.from('sellable_presentations').select('*').order('sku'),
      supabase.from('presentation_inventory').select('*').order('updated_at', { ascending: false }),
      supabase.from('inventory_movements').select('*').order('occurred_at', { ascending: false }).limit(250),
      supabase.from('packages').select('*').order('name'),
      supabase.from('package_components').select('*').order('created_at'),
      supabase.from('commercial_classifications').select('*').order('name'),
      supabase.from('catalog_classification_assignments').select('*').order('created_at'),
      supabase.from('catalog_resources').select('*').order('sort_order').order('created_at'),
    ]);

  return {
    products: requireData<Product[]>(products, 'No se pudieron cargar los productos'),
    presentations: requireData<Presentation[]>(presentations, 'No se pudieron cargar las presentaciones'),
    inventory: requireData<PresentationInventory[]>(inventory, 'No se pudo cargar el inventario'),
    movements: requireData<InventoryMovement[]>(movements, 'No se pudo cargar el historial'),
    packages: requireData<Package[]>(packages, 'No se pudieron cargar los paquetes'),
    components: requireData<PackageComponent[]>(components, 'No se pudieron cargar los componentes'),
    classifications: requireData<Classification[]>(classifications, 'No se pudieron cargar las clasificaciones'),
    assignments: requireData<ClassificationAssignment[]>(assignments, 'No se pudieron cargar las asignaciones'),
    resources: requireData<CatalogResource[]>(resources, 'No se pudieron cargar los recursos'),
  };
}

export async function saveProduct(input: Partial<Product> & Pick<Product, 'name'>): Promise<void> {
  const payload = {
    name: input.name.trim(),
    description: input.description?.trim() || null,
    usage_instructions: input.usage_instructions?.trim() || null,
    warnings: input.warnings?.trim() || null,
    is_active: input.is_active ?? true,
    updated_at: new Date().toISOString(),
  };

  const result = input.id
    ? await supabase.from('products').update(payload).eq('id', input.id)
    : await supabase.from('products').insert({ id: crypto.randomUUID(), ...payload });

  requireData(result, 'No se pudo guardar el producto');
}

export async function setProductActive(id: string, isActive: boolean): Promise<void> {
  const result = await supabase
    .from('products')
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq('id', id);
  requireData(result, 'No se pudo cambiar el estado del producto');
}

export async function archiveProduct(id: string): Promise<void> {
  const now = new Date().toISOString();
  const result = await supabase
    .from('products')
    .update({ is_active: false, archived_at: now, updated_at: now })
    .eq('id', id);
  requireData(result, 'No se pudo archivar el producto');
}

export async function savePresentation(
  input: Partial<Presentation> & Pick<Presentation, 'product_id' | 'sku' | 'current_price_amount_minor' | 'currency_code'>,
): Promise<void> {
  const payload = {
    product_id: input.product_id,
    sku: input.sku.trim(),
    variant_label: input.variant_label?.trim() || null,
    attributes: input.attributes ?? null,
    current_price_amount_minor: input.current_price_amount_minor,
    currency_code: input.currency_code.trim().toUpperCase(),
    is_active: input.is_active ?? true,
    updated_at: new Date().toISOString(),
  };
  const result = input.id
    ? await supabase.from('sellable_presentations').update(payload).eq('id', input.id)
    : await supabase.from('sellable_presentations').insert({ id: crypto.randomUUID(), ...payload });
  requireData(result, 'No se pudo guardar la presentación');
}

export async function setPresentationActive(id: string, isActive: boolean): Promise<void> {
  const result = await supabase
    .from('sellable_presentations')
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq('id', id);
  requireData(result, 'No se pudo cambiar el estado de la presentación');
}

export async function savePackage(input: Partial<Package> & Pick<Package, 'name' | 'current_price_amount_minor' | 'currency_code'>): Promise<string> {
  const payload = {
    name: input.name.trim(),
    description: input.description?.trim() || null,
    current_price_amount_minor: input.current_price_amount_minor,
    currency_code: input.currency_code.trim().toUpperCase(),
    is_active: input.is_active ?? true,
    valid_from: input.valid_from || null,
    valid_until: input.valid_until || null,
    updated_at: new Date().toISOString(),
  };
  const id = input.id ?? crypto.randomUUID();
  const result = input.id
    ? await supabase.from('packages').update(payload).eq('id', input.id)
    : await supabase.from('packages').insert({ id, ...payload });
  requireData(result, 'No se pudo guardar el paquete');
  return id;
}

export async function setPackageActive(id: string, isActive: boolean): Promise<void> {
  const result = await supabase
    .from('packages')
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq('id', id);
  requireData(result, 'No se pudo cambiar el estado del paquete');
}

export async function savePackageComponent(
  input: Partial<PackageComponent> & Pick<PackageComponent, 'package_id' | 'presentation_id' | 'quantity'>,
): Promise<void> {
  const payload = {
    package_id: input.package_id,
    presentation_id: input.presentation_id,
    quantity: input.quantity,
    is_active: input.is_active ?? true,
    updated_at: new Date().toISOString(),
  };
  const result = input.id
    ? await supabase.from('package_components').update(payload).eq('id', input.id)
    : await supabase.from('package_components').insert({ id: crypto.randomUUID(), ...payload });
  requireData(result, 'No se pudo guardar el componente');
}

export async function deletePackageComponent(id: string): Promise<void> {
  const result = await supabase.from('package_components').delete().eq('id', id);
  requireData(result, 'No se pudo eliminar el componente');
}

export async function saveClassification(
  input: Partial<Classification> & Pick<Classification, 'name'>,
): Promise<void> {
  const payload = {
    name: input.name.trim(),
    description: input.description?.trim() || null,
    parent_id: input.parent_id || null,
    is_active: input.is_active ?? true,
    updated_at: new Date().toISOString(),
  };
  const result = input.id
    ? await supabase.from('commercial_classifications').update(payload).eq('id', input.id)
    : await supabase.from('commercial_classifications').insert({ id: crypto.randomUUID(), ...payload });
  requireData(result, 'No se pudo guardar la clasificación');
}

export async function createClassificationAssignment(input: {
  classification_id: string;
  product_id?: string | null;
  package_id?: string | null;
}): Promise<void> {
  const result = await supabase.from('catalog_classification_assignments').insert({
    id: crypto.randomUUID(),
    classification_id: input.classification_id,
    product_id: input.product_id || null,
    package_id: input.package_id || null,
  });
  requireData(result, 'No se pudo crear la asignación');
}

export async function deleteClassificationAssignment(id: string): Promise<void> {
  const result = await supabase.from('catalog_classification_assignments').delete().eq('id', id);
  requireData(result, 'No se pudo eliminar la asignación');
}

export async function adjustInventory(input: {
  presentationId: string;
  quantityDelta: number;
  movementKind: 'stock_entry' | 'manual_adjustment';
  cause: string;
}): Promise<void> {
  const result = await supabase.rpc('adjust_presentation_inventory', {
    p_presentation_id: input.presentationId,
    p_quantity_delta: input.quantityDelta,
    p_movement_kind: input.movementKind,
    p_cause: input.cause.trim(),
  });
  requireData(result, 'No se pudo registrar el movimiento de inventario');
}

export async function uploadCatalogResource(input: {
  ownerType: 'product' | 'presentation' | 'package';
  ownerId: string;
  file: File;
  altText: string;
  sortOrder: number;
}): Promise<void> {
  const extension = input.file.name.split('.').pop()?.toLowerCase() || 'bin';
  const safeExtension = extension.replace(/[^a-z0-9]/g, '') || 'bin';
  const path = `${input.ownerType}/${input.ownerId}/${crypto.randomUUID()}.${safeExtension}`;
  const upload = await supabase.storage.from(CATALOG_BUCKET).upload(path, input.file, {
    cacheControl: '3600',
    upsert: false,
  });
  if (upload.error) {
    throw new Error(`No se pudo subir la imagen: ${upload.error.message}`);
  }

  const ownerColumns = {
    product_id: input.ownerType === 'product' ? input.ownerId : null,
    presentation_id: input.ownerType === 'presentation' ? input.ownerId : null,
    package_id: input.ownerType === 'package' ? input.ownerId : null,
  };
  const insert = await supabase.from('catalog_resources').insert({
    id: crypto.randomUUID(),
    ...ownerColumns,
    resource_kind: 'image',
    source_reference: path,
    alt_text: input.altText.trim() || null,
    sort_order: input.sortOrder,
    is_primary: false,
    is_active: true,
  });

  if (insert.error) {
    await supabase.storage.from(CATALOG_BUCKET).remove([path]);
    throw new Error(`No se pudo registrar la imagen: ${insert.error.message}`);
  }
}

export async function updateCatalogResource(
  id: string,
  patch: Partial<Pick<CatalogResource, 'alt_text' | 'sort_order' | 'is_active'>>,
): Promise<void> {
  const result = await supabase
    .from('catalog_resources')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('id', id);
  requireData(result, 'No se pudo actualizar el recurso');
}

export async function setPrimaryCatalogResource(id: string): Promise<void> {
  const result = await supabase.rpc('set_primary_catalog_resource', { p_resource_id: id });
  requireData(result, 'No se pudo seleccionar la imagen principal');
}

export async function replaceCatalogResource(resource: CatalogResource, file: File): Promise<void> {
  const extension = file.name.split('.').pop()?.toLowerCase() || 'bin';
  const safeExtension = extension.replace(/[^a-z0-9]/g, '') || 'bin';
  const owner = resource.product_id
    ? `product/${resource.product_id}`
    : resource.presentation_id
      ? `presentation/${resource.presentation_id}`
      : `package/${resource.package_id}`;
  const path = `${owner}/${crypto.randomUUID()}.${safeExtension}`;
  const upload = await supabase.storage.from(CATALOG_BUCKET).upload(path, file, {
    cacheControl: '3600',
    upsert: false,
  });
  if (upload.error) {
    throw new Error(`No se pudo subir el reemplazo: ${upload.error.message}`);
  }

  const update = await supabase
    .from('catalog_resources')
    .update({ source_reference: path, updated_at: new Date().toISOString() })
    .eq('id', resource.id);
  if (update.error) {
    await supabase.storage.from(CATALOG_BUCKET).remove([path]);
    throw new Error(`No se pudo registrar el reemplazo: ${update.error.message}`);
  }

  const removal = await supabase.storage.from(CATALOG_BUCKET).remove([resource.source_reference]);
  if (removal.error) {
    throw new Error(`La imagen fue reemplazada, pero el archivo anterior no pudo eliminarse: ${removal.error.message}`);
  }
}

export async function deleteCatalogResource(resource: CatalogResource): Promise<void> {
  const deletion = await supabase.from('catalog_resources').delete().eq('id', resource.id);
  if (deletion.error) {
    throw new Error(`No se pudo eliminar el recurso: ${deletion.error.message}`);
  }
  const removal = await supabase.storage.from(CATALOG_BUCKET).remove([resource.source_reference]);
  if (removal.error) {
    throw new Error(`El registro fue eliminado, pero el archivo no pudo eliminarse: ${removal.error.message}`);
  }
}

export function getCatalogResourceUrl(sourceReference: string): string {
  return supabase.storage.from(CATALOG_BUCKET).getPublicUrl(sourceReference).data.publicUrl;
}
